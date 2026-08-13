import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var history: [SharedFile] = ShareHistoryStore.all()
    @State private var isPickerPresented = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var qrSheetItem: QRSheetItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Share any photo or file to \"iShare\" from the share sheet, and it'll hand you back a QR code anyone can scan to download it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        isPickerPresented = true
                    } label: {
                        Label("Share a file from here instead", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isUploading)
                }

                if !history.isEmpty {
                    Section("Recent shares") {
                        ForEach(history) { item in
                            Button {
                                qrSheetItem = QRSheetItem(url: item.url, filename: item.filename)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.filename).font(.body)
                                    Text(item.sharedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("iShare")
            .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.item]) { result in
                handlePickedFile(result)
            }
            .sheet(item: $qrSheetItem) { item in
                QRCodeSheet(urlString: item.url, filename: item.filename)
            }
            .overlay {
                if isUploading {
                    ProgressView("Uploading…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Couldn't share file", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            Task { await upload(fileAt: url) }
        }
    }

    private func upload(fileAt url: URL) async {
        isUploading = true
        defer { isUploading = false }

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"

            let response = try await UploadManager.shared.upload(fileData: data, filename: filename, mimeType: mimeType)
            let record = SharedFile(id: response.id, filename: filename, url: response.url, expiresAt: response.expiresAt, sharedAt: Date())
            ShareHistoryStore.add(record)
            history = ShareHistoryStore.all()
            qrSheetItem = QRSheetItem(url: response.url, filename: filename)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct QRSheetItem: Identifiable {
    var id: String { url }
    let url: String
    let filename: String
}

private struct QRCodeSheet: View {
    let urlString: String
    let filename: String

    var body: some View {
        VStack(spacing: 20) {
            Text(filename).font(.headline)
            if let image = QRCodeGenerator.generate(from: urlString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 260, height: 260)
            }
            Text(urlString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
