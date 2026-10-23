import HyperVideoCore
import SwiftUI

/// Rotation, flip and cropping (custom fields or detected black bars).
struct CropSection: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    @Binding var detectedCrop: Crop?
    @State private var isDetecting = false

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
                Toggle("Flip", isOn: $settings.flipHorizontal).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Cropping") {
                Picker("Cropping", selection: $settings.pictureOptions.cropMode) {
                    ForEach(CropMode.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            modeDetails
        }
        .task(id: "\(info.url.path)|\(mode.rawValue)") { await detect() }
    }

    @ViewBuilder private var modeDetails: some View {
        switch mode {
        case .custom: customFields
        case .automatic, .conservative: detectedView
        case .none:
            Text("The picture is kept whole.").font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var detectedView: some View {
        HStack {
            if isDetecting {
                ProgressView().controlSize(.small)
                Text("Detecting…").foregroundStyle(Theme.muted)
            } else if let crop = detectedCrop {
                Text("Top \(crop.top) · Bottom \(crop.bottom) · Left \(crop.left) · Right \(crop.right)")
                    .monospacedDigit()
            }
            Spacer()
            Button("Detect", systemImage: "arrow.clockwise") { Task { await detect() } }
                .buttonStyle(.subtle)
                .disabled(isDetecting)
                .help("Analyse 10 frames for black bars again")
        }
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    cropField("Top", \.top)
                    cropField("Bottom", \.bottom)
                }
                GridRow {
                    cropField("Left", \.left)
                    cropField("Right", \.right)
                }
            }
            HStack {
                Button("Reset", systemImage: "arrow.counterclockwise") { settings.crop = .zero }
                    .buttonStyle(.subtle)
                    .disabled(settings.crop.isZero)
                if let size = info.displaySize, size.width > size.height {
                    Button("Crop to 2.39:1", systemImage: "rectangle.ratio.16.to.9") {
                        let bar = max(0, Int((size.height - size.width / 2.39) / 2))
                        settings.crop = Crop(top: bar, bottom: bar)
                    }
                    .buttonStyle(.subtle)
                }
            }
        }
    }

    private func cropField(_ title: LocalizedStringKey, _ edge: WritableKeyPath<Crop, Int>) -> some View {
        // Fits two per row in the 460 pt panel; the unit sits in the field's prompt.
        HStack(spacing: 6) {
            Text(title).frame(width: 64, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
            TextField(title, value: $settings.crop[dynamicMember: edge], format: .number, prompt: Text(verbatim: "px"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .help("Pixels")
            Stepper(title, value: $settings.crop[dynamicMember: edge], in: 0...4_000, step: 2).labelsHidden()
        }
    }

    private func detect() async {
        guard mode.detects else {
            detectedCrop = nil
            return
        }
        isDetecting = true
        let result = try? await CropDetector.detect(url: info.url, mode: mode)
        guard !Task.isCancelled else { return }
        detectedCrop = result
        isDetecting = false
    }
}
