import SwiftUI
import UniformTypeIdentifiers

struct EqualizerAPODocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= 2_000_000,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct EqualizerImportExportSheet: View {
    @ObservedObject var viewModel: EqualizerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var message: String?
    @State private var pendingImportText: String?
    @State private var pendingImportName = ""
    @State private var isTruncationConfirmationPresented = false

    var body: some View {
        NavigationStack {
            List {
                Button("Import Equalizer APO…") { isImporting = true }
                Button("Export Equalizer APO…") { isExporting = true }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Import / Export")
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let url = try result.get().first
                    guard let url else { return }
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) <= 2_000_000 else {
                        throw CocoaError(.fileReadTooLarge)
                    }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let name = url.deletingPathExtension().lastPathComponent
                    importPreset(text: text, name: name, allowTruncation: false)
                } catch {
                    message = LocalizedFormat.string(
                        "Import failed: %@",
                        error.localizedDescription
                    )
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: EqualizerAPODocument(text: EqualizerAPOExporter.export(viewModel.preset)),
                contentType: .plainText,
                defaultFilename: viewModel.preset.name
            ) { result in
                message = (try? result.get()) != nil
                    ? String(localized: "Export complete.")
                    : String(localized: "Export failed.")
            }
            .confirmationDialog(
                "This preset contains more than 16 bands.",
                isPresented: $isTruncationConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Import First 16 Bands") {
                    guard let pendingImportText else { return }
                    importPreset(
                        text: pendingImportText,
                        name: pendingImportName,
                        allowTruncation: true
                    )
                    clearPendingImport()
                }
                Button("Cancel", role: .cancel) { clearPendingImport() }
            } message: {
                Text("Only the first 16 filters can be imported. Remaining filters will be listed as warnings.")
            }
        }
    }

    private func importPreset(text: String, name: String, allowTruncation: Bool) {
        do {
            let imported = try AutoEqImporter.importEqualizerAPO(
                text,
                presetName: name,
                allowTruncation: allowTruncation
            )
            viewModel.applyImportedPreset(imported.preset)
            if imported.issues.isEmpty {
                message = LocalizedFormat.string(
                    "Imported %lld bands.",
                    Int64(imported.preset.bands.count)
                )
            } else {
                message = LocalizedFormat.string(
                    "Imported %lld bands with %lld warnings.",
                    Int64(imported.preset.bands.count),
                    Int64(imported.issues.count)
                )
            }
        } catch AutoEqImportError.tooManyFilters {
            pendingImportText = text
            pendingImportName = name
            isTruncationConfirmationPresented = true
        } catch {
            message = LocalizedFormat.string(
                "Import failed: %@",
                error.localizedDescription
            )
        }
    }

    private func clearPendingImport() {
        pendingImportText = nil
        pendingImportName = ""
        isTruncationConfirmationPresented = false
    }
}
