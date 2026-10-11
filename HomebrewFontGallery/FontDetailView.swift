import SwiftUI

/// The preview and details of the selected font.
struct FontDetailView: View {
    let font: FontCask
    let activity: GalleryModel.Activity?
    let status: GalleryModel.Status?

    @AppStorage("previewText") private var sampleText = ""
    @AppStorage("previewSize") private var previewSize = 36.0

    @State private var preview = PreviewState.loading
    @State private var selectedFaceID: FontFace.ID?

    static let defaultSampleText = "The quick brown fox jumps over the lazy dog."
    private static let iconWidth: CGFloat = 24

    private enum PreviewState: Equatable {
        case loading
        case faces([FontFace])
        /// The font has to be installed before it can be shown.
        case needsInstall
        case failed
    }

    var body: some View {
        Form {
            if activity?.token == font.token || status?.token == font.token {
                Section {
                    statusRow
                }
            }

            Section {
                previewRow
                if case .faces(let faces) = preview {
                    if faces.count > 1 {
                        Picker(selection: faceSelection(in: faces)) {
                            ForEach(faces) { face in
                                Text(face.name).tag(face.id)
                            }
                        } label: {
                            rowLabel("Style", systemImage: "bold.italic.underline")
                        }
                    }
                    LabeledContent {
                        TextField("Sample Text", text: $sampleText, prompt: Text(Self.defaultSampleText))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        rowLabel("Sample Text", systemImage: "character.cursor.ibeam")
                    }
                    LabeledContent {
                        HStack {
                            Slider(value: $previewSize, in: 12...96)
                                .frame(width: 160)
                            Text("\(Int(previewSize.rounded())) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    } label: {
                        rowLabel("Size", systemImage: "textformat.size")
                    }
                }
            } header: {
                Text(font.name)
            }

            Section {
                LabeledContent {
                    Text(font.isInstalled ? "Installed" : "Not Installed")
                } label: {
                    rowLabel("Status", systemImage: font.isInstalled ? "checkmark.circle" : "circle.dashed")
                }
                if let version = displayVersion {
                    LabeledContent {
                        Text(version)
                    } label: {
                        rowLabel("Version", systemImage: "number")
                    }
                }
                if !font.fontFiles.isEmpty {
                    LabeledContent {
                        Text(font.fontFiles.count == 1 ? "1 font file" : "\(font.fontFiles.count) font files")
                    } label: {
                        rowLabel("Contents", systemImage: "doc.on.doc")
                    }
                }
                if !font.alternateNames.isEmpty {
                    LabeledContent {
                        Text(font.alternateNames.joined(separator: ", "))
                    } label: {
                        rowLabel("Also Called", systemImage: "character.book.closed")
                    }
                }
                if let homepage = font.homepage, let host = homepage.host() {
                    LabeledContent {
                        Link(host, destination: homepage)
                    } label: {
                        rowLabel("Website", systemImage: "safari")
                    }
                }
                LabeledContent {
                    Text(font.token)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } label: {
                    rowLabel("Homebrew Name", systemImage: "shippingbox")
                }
            } footer: {
                if let caveat {
                    Text(caveat)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: PreviewKey(token: font.token, installedVersion: font.installedVersion)) {
            await loadPreview()
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusRow: some View {
        if let activity, activity.token == font.token {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Self.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                    Text("Homebrew is working on “\(activity.name)”.")
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

    // MARK: Preview

    @ViewBuilder
    private var previewRow: some View {
        switch preview {
        case .loading:
            HStack {
                Spacer()
                ProgressView("Loading Preview…")
                Spacer()
            }
            .padding(.vertical)
        case .faces(let faces):
            if let face = faces.first(where: { $0.id == selectedFaceID }) ?? faces.first {
                Text(sampleText.isEmpty ? Self.defaultSampleText : sampleText)
                    .font(Font(face.font(size: previewSize)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Preview of \(face.name)")
            }
        case .needsInstall:
            previewMessage("Install this font to preview it.", systemImage: "eye.slash")
        case .failed:
            previewMessage("The preview couldn’t be loaded. Check your internet connection, then select the font again.",
                           systemImage: "exclamationmark.triangle")
        }
    }

    private func previewMessage(_ message: String, systemImage: String) -> some View {
        Label {
            Text(message)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: Self.iconWidth)
        }
    }

    private struct PreviewKey: Equatable {
        let token: String
        let installedVersion: String?
    }

    private func loadPreview() async {
        preview = .loading
        let font = font
        if font.isInstalled {
            let faces = await Task.detached { FontPreview.faces(in: font.fontFiles) }.value
            guard !Task.isCancelled else { return }
            if !faces.isEmpty {
                show(faces)
                return
            }
        }
        guard font.previewDownloadURL != nil else {
            preview = .needsInstall
            return
        }
        do {
            let file = try await FontPreview.detailsFile(for: font)
            let faces = await Task.detached { FontPreview.faces(in: [file]) }.value
            guard !Task.isCancelled else { return }
            if faces.isEmpty {
                preview = .failed
            } else {
                show(faces)
            }
        } catch {
            guard !Task.isCancelled else { return }
            preview = .failed
        }
    }

    private func show(_ faces: [FontFace]) {
        if !faces.contains(where: { $0.id == selectedFaceID }) {
            selectedFaceID = faces.first?.id
        }
        preview = .faces(faces)
    }

    private func faceSelection(in faces: [FontFace]) -> Binding<FontFace.ID> {
        Binding(
            get: { faces.contains { $0.id == selectedFaceID } ? selectedFaceID! : faces[0].id },
            set: { selectedFaceID = $0 }
        )
    }

    // MARK: Details

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: Self.iconWidth)
        }
    }

    /// Homebrew calls a font with no version number "latest", which isn't worth a row.
    private var displayVersion: String? {
        let version = font.installedVersion ?? font.version
        return version.isEmpty || version == "latest" ? nil : version
    }

    private var caveat: String? {
        if font.needsInstaller {
            return "This font comes as an installer that needs an administrator, so it can’t be installed or uninstalled here."
        }
        if font.isDisabled {
            return "Homebrew no longer offers this font."
        }
        if font.isDeprecated {
            return "Homebrew plans to stop offering this font."
        }
        return nil
    }
}
