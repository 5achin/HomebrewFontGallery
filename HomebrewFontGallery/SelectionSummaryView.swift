import SwiftUI

/// What the details pane shows when several fonts are selected: how many, which of them
/// the action button applies to, and how the work on them is going.
struct SelectionSummaryView: View {
    let fonts: [FontCask]
    let action: GalleryModel.SelectionAction?
    let activity: GalleryModel.Activity?
    let status: GalleryModel.Status?

    private static let iconWidth: CGFloat = 24

    var body: some View {
        Form {
            if activity != nil || (status?.tokens.count ?? 0) > 1 {
                Section {
                    statusRow
                }
            }

            Section {
                LabeledContent {
                    Text(installedCount.formatted())
                } label: {
                    rowLabel("Installed", systemImage: "checkmark.circle")
                }
                LabeledContent {
                    Text((fonts.count - installedCount).formatted())
                } label: {
                    rowLabel("Not Installed", systemImage: "circle.dashed")
                }
            } header: {
                Text("\(fonts.count.formatted()) Fonts Selected")
            } footer: {
                if let footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                ForEach(fonts.prefix(Self.listLimit)) { font in
                    LabeledContent {
                        if activity?.token == font.token {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(font.isInstalled ? "Installed" : "Not Installed")
                        }
                    } label: {
                        Text(font.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } footer: {
                if fonts.count > Self.listLimit {
                    Text("And \((fonts.count - Self.listLimit).formatted()) more.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Naming every font of a long selection would make the pane slow to draw and to read.
    private static let listLimit = 50

    private var installedCount: Int {
        fonts.lazy.filter(\.isInstalled).count
    }

    /// Says what the button will do when it won't act on every selected font.
    private var footer: String? {
        guard let action, activity == nil, action.fonts.count != fonts.count else { return nil }
        if action.fonts.isEmpty {
            return action.kind == .install
                ? "The fonts that aren’t installed can’t be installed here."
                : "These fonts can’t be uninstalled here."
        }
        let count = GalleryModel.fontCount(action.fonts.count)
        return action.kind == .install
            ? "Install adds the \(count) that can be installed and leaves the rest as they are."
            : "Uninstall removes the \(count) that can be uninstalled here."
    }

    @ViewBuilder
    private var statusRow: some View {
        if let activity {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Self.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                    Group {
                        if activity.total > 1 {
                            Text("“\(activity.name)”, \(activity.position.formatted()) of \(activity.total.formatted()).")
                                .monospacedDigit()
                        } else {
                            Text("Homebrew is working on “\(activity.name)”.")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        } else if let status {
            HStack(spacing: 12) {
                Group {
                    switch status.kind {
                    case .success:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .cancelled:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                .font(.title3)
                .frame(width: Self.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                    Text(status.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: Self.iconWidth)
        }
    }
}
