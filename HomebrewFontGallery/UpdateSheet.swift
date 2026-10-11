import SwiftUI

/// The sheet that offers an update, shows it downloading, and reports how a check went.
struct UpdateSheet: View {
    let updater: UpdateModel
    let phase: UpdateModel.Phase
    /// True while Homebrew is installing or removing a font, when the app mustn't quit.
    let galleryIsBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch phase {
        case .checking: "Checking for Updates…"
        case .upToDate: "You’re Up to Date"
        case .available: "A New Version Is Available"
        case .downloading: "Downloading Update…"
        case .installing: "Installing Update…"
        case .failed(let title, _): title
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch phase {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            message("Homebrew Fonts Gallery \(updater.currentVersion) (build \(updater.currentBuild.formatted(.number.grouping(.never)))) is the newest version.")
        case .available(let update):
            message("Version \(update.version) (build \(update.build.formatted(.number.grouping(.never)))) is ready to install. You have build \(updater.currentBuild.formatted(.number.grouping(.never))). The app will close and reopen.")
            if galleryIsBusy {
                message("Wait for Homebrew to finish before installing the update.")
            }
        case .downloading(let update, let received):
            ProgressView(value: min(Double(received), Double(update.size)), total: Double(max(update.size, 1)))
            Text("\(Self.size(received)) of \(Self.size(Int64(update.size)))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .installing:
            ProgressView()
                .progressViewStyle(.linear)
        case .failed(_, let text):
            message(text)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .checking, .downloading:
            Button("Cancel", role: .cancel) {
                updater.cancel()
            }
            .keyboardShortcut(.cancelAction)
        case .available(let update):
            Button("Not Now", role: .cancel) {
                updater.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Install and Relaunch") {
                updater.install(update)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(galleryIsBusy)
        case .installing:
            EmptyView()
        case .upToDate, .failed:
            Button("OK") {
                updater.dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Check for Updates… in the app menu, dimmed while the update sheet is already up.
struct CheckForUpdatesButton: View {
    private let updater = UpdateModel.shared

    var body: some View {
        Button("Check for Updates…") {
            updater.checkNow()
        }
        .disabled(updater.phase != nil)
    }
}

/// One identity for the update sheet whatever it is showing, so it isn't put away and
/// brought back each time the phase changes.
struct UpdatePresentation: Identifiable {
    let id = 0

    init(_ phase: UpdateModel.Phase) {}
}
