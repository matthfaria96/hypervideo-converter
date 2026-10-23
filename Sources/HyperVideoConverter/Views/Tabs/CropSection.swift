import HyperVideoCore
import SwiftUI

/// Rotation, flip and cropping (custom fields or detected black bars).
struct CropSection: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    @Binding var detectedCrop: Crop?
    @State private var isDetecting = false
    /// Bumped by the Detect button: re-runs the detection task, which SwiftUI cancels
    /// when the video or mode changes, so a stale result never lands.
    @State private var detectRun = 0

    private var mode: CropMode { settings.pictureOptions.cropMode }

    var body: some View {
        SettingsSection(title: "Orientation & Cropping", symbol: "crop") {
            SettingRow(title: "Rotate") {
                Picker("Rotate", selection: $settings.rotation) {
                    ForEach(Rotation.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Flip horizontally") {
                Toggle("Flip", isOn: $settings.flipHorizontal).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingRow(title: "Cropping") {
                Picker("Cropping", selection: $settings.pictureOptions.cropMode) {
                    ForEach(CropMode.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            modeDetails
                .id(mode)
                .motionTransition(.content)
        }
        .motion(value: mode)
        .task(id: "\(info.url.path)|\(mode.rawValue)|\(detectRun)") { await detect() }
    }

    @ViewBuilder private var modeDetails: some View {
        switch mode {
        case .custom: customFields
        case .automatic, .conservative: detectedView
        case .none:
            Text("The picture is kept whole.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var detectedView: some View {
        HStack(spacing: Spacing.m) {
            if isDetecting {
                ProgressView().controlSize(.small)
                Text("Detecting…").foregroundStyle(.secondary)
            } else if let crop = detectedCrop {
                Text("Top \(crop.top) · Bottom \(crop.bottom) · Left \(crop.left) · Right \(crop.right)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            Button("Detect", systemImage: "arrow.clockwise") { detectRun += 1 }
                .compatGlassButtonStyle()
                .controlSize(.small)
                .disabled(isDetecting)
                .help("Analyse 10 frames for black bars again")
        }
        .motion(Motion.quick, value: isDetecting)
    }

    /// Four labelled fields on one grid, and the shortcuts under them.
    private var customFields: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
                GridRow {
                    cropField("Top", \.top)
                    cropField("Bottom", \.bottom)
                }
                GridRow {
                    cropField("Left", \.left)
                    cropField("Right", \.right)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { shortcuts }
                VStack(alignment: .leading, spacing: Spacing.s) { shortcuts }
            }
            .compatGlassButtonStyle()
            .controlSize(.small)
        }
    }

    @ViewBuilder private var shortcuts: some View {
        Button("Reset", systemImage: "arrow.counterclockwise") { settings.crop = .zero }
            .disabled(settings.crop.isZero)
        if let size = info.displaySize, size.width > size.height {
            Button("Crop to 2.39:1", systemImage: "rectangle.ratio.16.to.9") {
                let bar = max(0, Int((size.height - size.width / 2.39) / 2))
                settings.crop = Crop(top: bar, bottom: bar)
            }
            .fixedSize()
        }
    }

    private func cropField(_ title: LocalizedStringKey, _ edge: WritableKeyPath<Crop, Int>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: Spacing.xs) {
                TextField(title, value: $settings.crop[dynamicMember: edge], format: .number, prompt: Text(verbatim: "px"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .help("Pixels")
                Stepper(title, value: $settings.crop[dynamicMember: edge], in: 0...4_000, step: 2).labelsHidden()
            }
        }
    }

    private func detect() async {
        detectedCrop = nil
        guard mode.detects else {
            isDetecting = false
            return
        }
        isDetecting = true
        let url = info.url
        let result = try? await CropDetector.detect(url: url, mode: mode)
        // A cancelled run was replaced by a newer one, which owns `isDetecting` now.
        guard !Task.isCancelled, url == info.url else { return }
        detectedCrop = result
        isDetecting = false
    }
}
