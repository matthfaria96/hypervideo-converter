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

    /// Finished jobs kept in History; the oldest go first.
    nonisolated static let historyLimit = 200

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Running jobs the user removed; they leave the list once their encode stops.
    @ObservationIgnored private var pendingRemoval: Set<UUID> = []
    @ObservationIgnored private var startTimes: [UUID: Date] = [:]
    /// Progress of the running jobs, outside `jobs` so ticks don't redraw the whole list.
    @ObservationIgnored private var progressBoxes: [UUID: JobProgress] = [:]
    @ObservationIgnored private let engine = TranscodeEngine()
    @ObservationIgnored private let saver: CoalescingSaver<[EncodeJob]>
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: any QueueNotifying
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var dockThrottle = DockThrottle()
    /// False while the saved queue's files are being looked up after launch.
    private(set) var isReady = true
    /// Called with the sources of jobs that left the queue (removed, cleared, trimmed).
    @ObservationIgnored var onJobsRemoved: (@MainActor ([EncodeJob]) -> Void)?
    /// Jobs that completed or failed since the queue last ran dry.
    private var batch = (done: 0, failed: 0)

    /// `directory`, `defaults` and `notifier` override persistence, preferences and
    /// notifications (tests). `saveDelay` is how long changes wait to be written together
    /// (zero writes at once); `resolvesInBackground` false does the launch work inline.
    init(directory: URL? = nil, defaults: UserDefaults = .standard, notifier: (any QueueNotifying)? = nil,
         saveDelay: TimeInterval = 0.5, resolvesInBackground: Bool = true) {
        let store = JSONStore<[EncodeJob]>(fileName: "queue.json", directory: directory)
        saver = CoalescingSaver(store: store, delay: saveDelay)
        self.defaults = defaults
        self.notifier = notifier ?? SystemNotifier(defaults: defaults)
        if resolvesInBackground {
            jobs = []
            isReady = false
            launchTask = Task { await finishLaunch(store: store) }
        } else {
            let saved = store.load() ?? []
            jobs = Self.restored(saved).map { $0.resolvingBookmarks() }
            if jobs != saved { persist() }
            Self.sweepStaleWorkDirectories(in: jobs)
        }
    }

    /// Saved jobs as they stand after a relaunch, oldest history trimmed.
    private nonisolated static func restored(_ saved: [EncodeJob]) -> [EncodeJob] {
        pruned(saved.map { $0.restoredAfterRelaunch().droppingBookmarksWhenCompleted() })
    }

    /// Waits until the saved queue's files have been located (see `isReady`).
    func whenReady() async { await launchTask?.value }

    /// Reads queue.json, follows bookmarks and removes leftover work folders away from the
    /// main thread, then puts the saved jobs ahead of any the user added meanwhile.
    private func finishLaunch(store: JSONStore<[EncodeJob]>) async {
        let (saved, resolved) = await Task.detached(priority: .utility) {
            let saved = store.load() ?? []
            let resolved = QueueStore.restored(saved).map { $0.resolvingBookmarks() }
            QueueStore.sweepStaleWorkDirectories(in: resolved, skipping: [])
            return (saved, resolved)
        }.value
        let loadedIDs = Set(resolved.map(\.id))
        jobs = resolved + jobs.filter { !loadedIDs.contains($0.id) }
        isReady = true
        if jobs != saved { persist() }
        schedule()
    }

    /// Drops the oldest finished jobs beyond `historyLimit`.
    nonisolated static func pruned(_ jobs: [EncodeJob], limit: Int = historyLimit) -> [EncodeJob] {
        var excess = jobs.filter(\.state.isFinished).count - limit
        guard excess > 0 else { return jobs }
        return jobs.filter { job in
            guard excess > 0, job.state.isFinished else { return true }
            excess -= 1
            return false
        }
    }

    // MARK: Derived state

    var pendingCount: Int { jobs.filter { $0.state == .queued }.count }
    var runningCount: Int { jobs.filter(\.state.isRunning).count }
    /// Jobs that completed or failed in the current run.
    var batchFinishedCount: Int { batch.done + batch.failed }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }
    /// Every destination a job could still write: only completed jobs give theirs up,
    /// since cancelled or failed ones can be retried.
    var takenDestinations: Set<URL> { Set(jobs.filter { !$0.isCompleted }.map(\.destination)) }

    /// How far each running job is, in list order.
    var runningFractions: [Double] {
        jobs.compactMap { job in job.state.isRunning ? progressBoxes[job.id]?.fraction ?? 0 : nil }
    }

    /// Average progress across running jobs, nil when idle.
    var overallProgress: Double? {
        let values = progressBoxes.values.map(\.fraction)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The progress of `id`; views that show it observe only this object.
    func progress(for id: UUID) -> JobProgress {
        progressBoxes[id] ?? JobProgress()
    }

    /// Speed and time left for a running job.
    func rate(for job: EncodeJob, now: Date = Date()) -> EncodeRate? {
        guard job.state.isRunning, let started = startTimes[job.id] else { return nil }
        return EncodeRate(progress: progress(for: job.id).fraction, elapsed: now.timeIntervalSince(started),
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

    /// Requeues a finished job, picking a new name if its output is taken. The file check
    /// runs off the main thread; await the task to know when the job is requeued.
    @discardableResult
    func retry(_ id: UUID) -> Task<Void, Never> {
        guard let destination = jobs.first(where: { $0.id == id })?.destination else { return Task {} }
        return Task {
            let exists = await Task.detached(priority: .userInitiated) {
                FileManager.default.fileExists(atPath: destination.path)
            }.value
            requeue(id, destinationExists: exists)
        }
    }

    private func requeue(_ id: UUID, destinationExists: Bool) {
        replace(id) { job in
            var retried = job.with(state: .queued)
            let othersTaken = Set(jobs.filter { $0.id != id && !$0.isCompleted }.map(\.destination))
            if othersTaken.contains(job.destination) || destinationExists {
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
        let running = ids.filter { tasks[$0] != nil }
        pendingRemoval.formUnion(running)
        running.forEach { tasks[$0]?.cancel() }
        removeJobs { ids.contains($0.id) && !running.contains($0.id) && !$0.state.isRunning }
    }

    func clearFinished() { removeJobs { $0.state.isFinished } }

    private func removeJobs(where shouldRemove: (EncodeJob) -> Bool) {
        let removed = jobs.filter(shouldRemove)
        jobs = jobs.filter { !shouldRemove($0) }
        persist()
        if !removed.isEmpty { onJobsRemoved?(removed) }
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
        guard isProcessing, isReady else { return }
        Self.nextToLaunch(jobs, limit: maxConcurrent).forEach(launch)
        if runningCount == 0 && pendingCount == 0 { isProcessing = false }
    }

    private func launch(_ job: EncodeJob) {
        replace(job.id) { $0.with(state: .running(progress: 0)) }
        startTimes[job.id] = Date()
        progressBoxes[job.id] = JobProgress()
        let engine = engine
        let throttle = ProgressThrottle()
        // QueueStore lives for the whole app session, so strong captures are safe here.
        tasks[job.id] = Task {
            let scoped = FileBookmarks.startAccessing(job.accessedURLs)
            defer { FileBookmarks.stopAccessing(scoped) }
            let result: Result<TranscodeOutput, Error>
            do {
                let output = try await engine.transcode(
                    source: job.source, destination: job.destination, settings: job.settings,
                    subtitleFiles: job.subtitleFiles ?? [], workTag: job.id
                ) { progress in
                    guard throttle.accepts(progress) else { return }
                    Task { @MainActor in self.updateProgress(job.id, progress) }
                }
                result = .success(output)
            } catch {
                result = .failure(error)
            }
            finish(job, result: result)
        }
    }

    private func updateProgress(_ id: UUID, _ progress: Double) {
        guard let box = progressBoxes[id] else { return }
        box.advance(to: progress)
        refreshDock(force: false)
    }

    private func finish(_ job: EncodeJob, result: Result<TranscodeOutput, Error>) {
        tasks[job.id] = nil
        progressBoxes[job.id] = nil
        let elapsed = Date().timeIntervalSince(startTimes.removeValue(forKey: job.id) ?? Date())
        if pendingRemoval.remove(job.id) != nil {
            removeJobs { $0.id == job.id }
        } else {
            record(job, result: result, elapsed: elapsed)
        }
        trimHistory()
        schedule()
        reportIfDrained()
    }

    private func record(_ job: EncodeJob, result: Result<TranscodeOutput, Error>, elapsed: TimeInterval) {
        switch result {
        case .success(let output):
            let completed = JobState.completed(outputBytes: output.bytes, elapsed: elapsed)
            // The engine may have picked a new name if the destination appeared mid-encode.
            replace(job.id) { $0.with(destination: output.url).with(state: completed).droppingBookmarksWhenCompleted() }
            batch.done += 1
            notifier.jobFinished(job.with(destination: output.url), succeeded: true)
        case .failure(is CancellationError):
            replace(job.id) { $0.with(state: .cancelled) }
        case .failure(let error):
            appLog.error("Job failed: \(error.localizedDescription, privacy: .public)")
            let message = JobErrorMessage.text(for: error)
            replace(job.id) { $0.with(state: .failed(message: message)) }
            batch.failed += 1
            notifier.jobFinished(job, succeeded: false)
        }
    }

    private func trimHistory() {
        let kept = Self.pruned(jobs)
        guard kept.count != jobs.count else { return }
        let keptIDs = Set(kept.map(\.id))
        let removed = jobs.filter { !keptIDs.contains($0.id) }
        jobs = kept
        persist()
        onJobsRemoved?(removed)
    }

    /// Once nothing is running or waiting, sums up the run (unless every job was cancelled).
    private func reportIfDrained() {
        guard runningCount == 0, pendingCount == 0 else { return }
        let finished = batch
        batch = (0, 0)
        if finished.done + finished.failed > 0 { notifier.queueFinished(done: finished.done, failed: finished.failed) }
    }

    private func replace(_ id: UUID, _ transform: (EncodeJob) -> EncodeJob) {
        jobs = jobs.map { $0.id == id ? transform($0) : $0 }
        persist()
    }

    /// Stops running encodes before quitting and waits for them to clean up their work
    /// folders. Interrupted jobs go back to queued so they resume after relaunch.
    func stopForQuit() async {
        isProcessing = false
        await launchTask?.value
        let interrupted = tasks
        interrupted.values.forEach { $0.cancel() }
        for task in interrupted.values { await task.value }
        settleInterrupted(Set(interrupted.keys))
    }

    /// Drops interrupted jobs the user had removed and requeues the rest, then saves.
    private func settleInterrupted(_ interrupted: Set<UUID>) {
        let dropped = pendingRemoval
        pendingRemoval = []
        removeJobs { dropped.contains($0.id) }
        jobs = jobs.map { interrupted.contains($0.id) ? $0.with(state: .queued) : $0 }
        persist()
        flushPersistence()
    }

    /// For logout and shutdown, which can't wait: cancels encodes, requeues them and
    /// removes their work folders now (best effort; a writer may still be closing).
    /// The launch sweep catches anything left behind.
    func stopImmediately() {
        isProcessing = false
        let interrupted = tasks
        interrupted.values.forEach { $0.cancel() }
        let owners = Set(interrupted.keys).union(pendingRemoval)
        let swept = jobs.filter { owners.contains($0.id) }
        settleInterrupted(Set(interrupted.keys))
        Self.sweepStaleWorkDirectories(in: swept, onlyOwnedBy: owners)
    }

    /// Removes work folders left behind by encodes interrupted by a crash or forced quit,
    /// next to `sweptJobs`' outputs. Folders of `running` jobs are never touched; when
    /// `owners` is given, only folders tagged with one of those job ids go.
    nonisolated static func sweepStaleWorkDirectories(in sweptJobs: [EncodeJob], skipping running: Set<UUID> = [],
                                                      onlyOwnedBy owners: Set<UUID>? = nil) {
        let folders = Set(sweptJobs.map { $0.destination.deletingLastPathComponent() })
        let manager = FileManager.default
        for folder in folders {
            let contents = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            contents.filter { shouldSweep($0.lastPathComponent, skipping: running, onlyOwnedBy: owners) }
                .forEach { try? manager.removeItem(at: $0) }
        }
    }

    private nonisolated static func shouldSweep(_ name: String, skipping running: Set<UUID>,
                                                onlyOwnedBy owners: Set<UUID>?) -> Bool {
        guard WorkFolder.isWorkFolder(name: name) else { return false }
        let owner = WorkFolder.jobID(fromName: name)
        if let owner, running.contains(owner) { return false }
        guard let owners else { return true }
        return owner.map(owners.contains) ?? false
    }

    /// A no-op until the saved queue has loaded, so a partial list never overwrites it;
    /// the launch task saves the merged list.
    private func persist() {
        guard isReady else { return }
        saver.save(jobs)
    }

    /// Writes any change still waiting for its turn (called when the app quits).
    /// Skipped before the saved queue has loaded, for the same reason as `persist`.
    func flushPersistence() {
        guard isReady else { return }
        saver.flush()
    }

    /// Progress ticks pass `force: false` and are throttled; state changes always refresh.
    private func refreshDock(force: Bool = true) {
        let now = Date()
        guard dockThrottle.accepts(now: now, force: force) else { return }
        dockThrottle = dockThrottle.recording(now)
        SystemIntegration.updateDock(progress: overallProgress, pendingCount: pendingCount)
    }
}

private extension EncodeJob {
    /// A copy pointing at the file the engine actually wrote.
    func with(destination: URL) -> EncodeJob {
        guard destination != self.destination else { return self }
        var copy = self
        copy.destination = destination
        return copy
    }
}
