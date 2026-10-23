import HyperVideoCore
import SwiftUI

/// "By quality" or "By size": the two ways to compress.
struct CompressGoalPicker: View {
    @Environment(AppModel.self) private var model
    /// The last target used, so switching back to "By size" restores it.
    @AppStorage("lastCompressTargetMB") private var lastTarget = 16.0

    var body: some View {
        Picker("Compress", selection: Binding(
            get: { model.compressTargetMB != nil },
            set: { bySize in model.compressTargetMB = bySize ? lastTarget : nil }
        )) {
            Label("By Quality", systemImage: "dial.medium").tag(false)
            Label("By Size", systemImage: "scalemass").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .onChange(of: model.compressTargetMB) { _, value in if let value { lastTarget = value } }
    }
}

/// "At most [16] MB per video", with shortcuts for where the video is going.
struct TargetSizeFields: View {
    @Environment(AppModel.self) private var model

    private static let shortcuts: [(name: LocalizedStringKey, symbol: String, mb: Double)] = [
        ("Discord", "bubble.left.and.bubble.right", 10),
        ("WhatsApp", "phone.bubble", 16),
        ("E-mail", "envelope", 25),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Text("At most")
                TextField("MB", value: mb, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Stepper("MB", value: mb, in: 1...10_000, step: 1).labelsHidden()
                Text("MB per video").foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.s) {
                ForEach(Self.shortcuts, id: \.mb) { shortcut in
                    Button {
                        model.compressTargetMB = shortcut.mb
                    } label: {
                        Label { Text(shortcut.name) } icon: { Image(systemName: shortcut.symbol) }
                    }
                    .compatGlassButtonStyle()
                    .controlSize(.small)
                    .help(Text("\(Int(shortcut.mb)) MB"))
                }
            }
            notes
        }
    }

    private var mb: Binding<Double> {
        Binding(get: { model.compressTargetMB ?? 16 }, set: { model.compressTargetMB = $0 })
    }

    /// Which videos can't reach the target, and which get a smaller picture to keep it sharp.
    @ViewBuilder
    private var notes: some View {
        let plans = model.sources.filter { model.inspectorTargetIDs.contains($0.id) }.compactMap { model.targetPlan(for: $0) }
        let tooBig = plans.filter { !$0.fits }.count
        let downscaled = plans.filter { $0.settings.maxResolution != .source }.count
        if tooBig > 0 {
            StatusBanner(messages: [String(localized: "\(tooBig) video(s) can't get this small; they'll come out as small as possible.")])
        }
        if downscaled > 0 {
            Label("To stay sharp at this size, \(downscaled) video(s) get a smaller resolution.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("The audio becomes AAC and the video HEVC, at the bitrate that fills the target.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
