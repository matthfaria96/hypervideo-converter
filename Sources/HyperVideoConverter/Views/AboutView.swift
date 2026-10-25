import AppKit
import SwiftUI

/// The About tab of Settings: centered and quiet, like About This Mac.
struct AboutView: View {
    @State private var showLicenses = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.bottom, 18)
                Text(verbatim: "HyperVideo Converter")
                    .font(.system(size: 24, weight: .semibold))
                Text(String(format: String(localized: "Version %@"), Self.marketing) + " (" + Self.build + ")")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)

                Text("HyperVideo Converter converts and compresses videos in batches with Apple's own media frameworks, so H.264, HEVC and ProRes run on the Mac's hardware encoders. It also trims, crops, filters and adds subtitles.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 460)
                    .padding(.top, 26)

                Text("HyperVideo Converter is free software under the GNU GPL v3.0.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .padding(.top, 14)

                HStack(spacing: 18) {
                    Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                        .font(.system(size: 12))
                    Button("Open-source licenses") { showLicenses = true }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .frame(height: 440)
        .sheet(isPresented: $showLicenses) { OpenSourceLicensesView() }
    }

    private static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

/// The license of HyperVideo Converter, shown in full so the notice travels with the app.
struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private let notice = """
    Copyright (C) 2026 Matheus Faria
    Source code: https://github.com/matthfaria96/hypervideo-converter

    HyperVideo Converter is free software: you can redistribute it and/or modify it under \
    the terms of the GNU General Public License as published by the Free Software \
    Foundation, either version 3 of the License, or (at your option) any later version. \
    It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of \
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Full license text: https://www.gnu.org/licenses/gpl-3.0.html
    """

    /// Attribution the models' licences ask for (also in Contents/Resources/Licenses/THIRD-PARTY-NOTICES.txt).
    private static let models = """
    Upscayl Standard, Upscayl Lite and Digital Art: from the Upscayl project \
    (github.com/upscayl/upscayl), AGPL-3.0.
    High Fidelity: 4xHFA2k by Helaman (Philip Hofmann), CC BY 4.0 \
    (creativecommons.org/licenses/by/4.0), converted to ncnn by Upscayl.
    Real-ESRGAN: Copyright (c) 2021, Xintao Wang, BSD 3-Clause License.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open-source licenses")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("HyperVideo Converter is open source. Its license is reproduced below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "HyperVideo Converter")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "GNU General Public License v3.0")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(verbatim: notice)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "Upscayl (upscayl-bin) · Real-ESRGAN")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "GNU Affero General Public License v3.0")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text("AI Upscale runs Upscayl as a separate program. Its licence is in the app (Contents/Resources/Licenses) and its source code is at github.com/upscayl/upscayl-ncnn.")
                            .font(.system(size: 11.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "AI models")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: Self.models)
                            .font(.system(size: 11.5))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 480)
    }
}
