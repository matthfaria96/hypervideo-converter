import Foundation
import HyperVideoCore
import Observation

private extension EncodeJob {
    var isCompleted: Bool {
        if case .completed = state { return true }
        return false
    }
}

@Observable
@MainActor
final class QueueStore {
    private(set) var jobs: [EncodeJob]
    /// When false, running jobs finish but no new ones start.
    private(set) var isProcessing = false

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var startTimes: [UUID: Date] = [:]
    private let engine = TranscodeEngine()
    private let store: JSONStore<[EncodeJob]>
    private let defaults: UserDefaults

    /// `directory` and `defaults` override persistence and preferences (tests).
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        store = JSONStore(fileName: "queue.json", directory: directory)
        self.defaults = defaults
        let saved = store.load() ?? []
        jobs = saved.map { $0.restoredAfterRelaunch().resolvingBookmarks() }
        if jobs != saved { store.save(jobs) }
        sweepStaleWorkDirectories()
    }

    // MARK: Derived state

    var pendingCount: Int { jobs.filter { $0.state == .queued }.count }
    var runningCount: Int { jobs.filter(\.state.isRunning).count }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }
    /// Every destination a job could still write: only completed jobs give theirs up,
    /// since cancelled or failed ones can be retried.
    var takenDestinations: Set<URL> { Set(jobs.filter { !$0.isCompleted }.map(\.destination)) }

    /// Average progress across running jobs, nil when idle.
    var overallProgress: Double? {
        let values = jobs.compactMap { job -> Double? in
            if case .running(let progress) = job.state { return progress }
            return nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Speed and time left for a running job.
    func rate(for job: EncodeJob, now: Date = Date()) -> EncodeRate? {
        guard case .running(let progress) = job.state, let started = startTimes[job.id] else { return nil }
        return EncodeRate(progress: progress, elapsed: now.timeIntervalSince(started),
                          mediaDuration: job.mediaDuration, frameRate: job.frameRate)
    }

    /// Time until every running job is done, once their rates have settled.
    var remainingForRunning: TimeInterval? {
        let now = Date()
        return jobs.compactMap { rate(for: $0, now: now)?.remaining }.max()
    }

    private var maxConcurrent: Int {
        let value = defaults.integer(forKey: PreferenceKey.maxConcurrentJobs)
        return min(max(value, 1), 4)
    }

    // MARK: Mutations

    func add(_ newJobs: [EncodeJob]) {
        jobs = jobs + newJobs.map { $0.bookmarked() }
        persist()
        if defaults.bool(forKey: PreferenceKey.autoStartQueue) { start() } else { refreshDock() }
    }

    func start() {
        isProcessing = true
        schedule()
    }

    func pause() {
        isProcessing = false
        refreshDock()
    }

    func cancel(_ id: UUID) {
        if let task = tasks[id] {
            task.cancel()
        } else {
            replace(id) { $0.with(state: .cancelled) }
        }
    }

    func cancelAll() {
        isProcessing = false
        jobs.filter { !$0.state.isFinished }.forEach { cancel($0.id) }
    }

    func retry(_ id: UUID) {
        replace(id) { job in
            var retried = job.with(state: .queued)
            let othersTaken = Set(jobs.filter { $0.id != id && !$0.isCompleted }.map(\.destination))
            if othersTaken.contains(job.destination) || FileManager.default.fileExists(atPath: job.destination.path) {
                let suffix = defaults.string(forKey: PreferenceKey.outputSuffix) ?? ""
                retried.destination = OutputNaming.destination(
                    for: job.source, in: job.destination.deletingLastPathComponent(),
                    container: job.settings.container, suffix: suffix, taken: othersTaken
                )
            }
            return retried
        }
        schedule()
    }

    func remove(_ ids: Set<UUID>) {
        ids.forEach { tasks[$0]?.cancel() }
        jobs = jobs.filter { !ids.contains($0.id) || $0.state.isRunning }
        persist()
    }

    func clearFinished() {
        jobs = jobs.filter { !$0.state.isFinished }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = jobs
        reordered.move(fromOffsets: source, toOffset: destination)
        jobs = reordered
        persist()
    }

    // MARK: Ordering (pending jobs run top to bottom)

    enum Movement { case up, down, top }

    func canMove(_ id: UUID, _ movement: Movement) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
        return movement == .down ? index < jobs.count - 1 : index > 0
    }

    func move(_ id: UUID, _ movement: Movement) {
        guard canMove(id, movement), let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch movement {
        case .up: move(fromOffsets: [index], toOffset: index - 1)
        case .down: move(fromOffsets: [index], toOffset: index + 2)
        case .top: move(fromOffsets: [index], toOffset: 0)
        }
    }

    /// Drag and drop: `id` takes `target`'s place, so dragging down lands after it
    /// and dragging up lands before it.
    func move(_ id: UUID, onto target: UUID) {
        guard id != target, let index = jobs.firstIndex(where: { $0.id == id }),
              let destination = jobs.firstIndex(where: { $0.id == target }) else { return }
        move(fromOffsets: [index], toOffset: destination > index ? destination + 1 : destination)
    }

    /// The queued jobs to start, in list order, filling up to `limit` running encodes.
    static func nextToLaunch(_ jobs: [EncodeJob], limit: Int) -> [EncodeJob] {
        let running = jobs.filter(\.state.isRunning).count
        return Array(jobs.filter { $0.state == .queued }.prefix(max(limit - running, 0)))
    }

    // MARK: Scheduling

    private func schedule() {
        defer { refreshDock() }
        guard isProcessing else { return }
        Self.nextToLaunch(jobs, limit: maxConcurrent).forEach(launch)
        if runningCount == 0 && pendingCount == 0 { isProcessing = false }
    }

    private func launch(_ job: EncodeJob) {
        replace(job.id) { $0.with(state: .running(progress: 0)) }
        startTimes[job.id] = Date()
        let engine = engine
        // QueueStore lives for the whole app session, so strong captures are safe here.
        tasks[job.id] = Task {
            let scoped = FileBookmarks.startAccessing(job.accessedURLs)
            defer { FileBookmarks.stopAccessing(scoped) }
            let result: Result<Int64, Error>
            do {
                let bytes = try await engine.run(
                    source: job.source, destination: job.destination, settings: job.settings,
                    subtitleFiles: job.subtitleFiles ?? []
                ) { progress in
                    Task { @MainActor in self.updateProgress(job.id, progress) }
                }
                result = .success(bytes)
            } catch {
                result = .failure(error)
            }
            finish(job, result: result)
        }
    }

    private func updateProgress(_ id: UUID, _ progress: Double) {
        guard let job = jobs.first(where: { $0.id == id }), job.state.isRunning else { return }
        replace(id, persisting: false) { $0.with(state: .running(progress: progress)) }
        refreshDock()
    }

    private func finish(_ job: EncodeJob, result: Result<Int64, Error>) {
        tasks[job.id] = nil
        let elapsed = Date().timeIntervalSince(startTimes.removeValue(forKey: job.id) ?? Date())
        switch result {
        case .success(let bytes):
            replace(job.id) { $0.with(state: .completed(outputBytes: bytes, elapsed: elapsed)) }
            SystemIntegration.notify(title: "Conversion finished", body: job.destination.lastPathComponent)
            if defaults.bool(forKey: PreferenceKey.revealOnCompletion) {
                SystemIntegration.reveal([job.destination])
            }
        case .failure(is CancellationError):
            replace(job.id) { $0.with(state: .cancelled) }
        case .failure(let error):
            appLog.error("Job failed: \(error.localizedDescription, privacy: .public)")
            replace(job.id) { $0.with(state: .failed(message: error.localizedDescription)) }
            SystemIntegration.notify(title: "Conversion failed", body: job.source.lastPathComponent)
        }
        schedule()
    }

    private func replace(_ id: UUID, persisting: Bool = true, _ transform: (EncodeJob) -> EncodeJob) {
        jobs = jobs.map { $0.id == id ? transform($0) : $0 }
        if persisting { persist() }
    }

    /// Stops running encodes before quitting and waits for them to clean up their work
    /// folders. Interrupted jobs go back to queued so they resume after relaunch.
    func stopForQuit() async {
        isProcessing = false
        let interrupted = tasks
        interrupted.values.forEach { $0.cancel() }
        for task in interrupted.values { await task.value }
        jobs = jobs.map { interrupted[$0.id] != nil ? $0.with(state: .queued) : $0 }
        persist()
    }

    /// Removes work folders left behind by encodes interrupted by a crash or forced quit.
    private func sweepStaleWorkDirectories() {
        let folders = Set(jobs.map { $0.destination.deletingLastPathComponent() })
        let manager = FileManager.default
        for folder in folders {
            let contents = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            contents.filter { $0.lastPathComponent.hasPrefix(".hypervideo-") }
                .forEach { try? manager.removeItem(at: $0) }
        }
    }

    private func persist() { store.save(jobs) }

    private func refreshDock() {
        SystemIntegration.updateDock(progress: overallProgress, pendingCount: pendingCount)
    }
}
