import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var history: [SharedFile] = ShareHistoryStore.all()
    @State private var isPickerPresented = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var qrSheetItem: QRSheetItem?
    @State private var motion = TiltMotionManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 20) {
                    VStack(spacing: 20) {
                        introCard
                        if !history.isEmpty {
                            recentSharesSection
                        }
                    }
                    .padding()
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("iShare")
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
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
        .preferredColorScheme(.dark)
    }

    // The intro block is ONE glass card. The button inside it stays a plain
    // prominent style rather than its own glass -- glass can't cleanly
    // sample another glass surface behind it, so nesting two here would
    // fight the effect rather than showcase it.
    private var introCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share any photo or file to \"iShare\" from the share sheet, and it'll hand you back a QR code anyone can scan to download it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                isPickerPresented = true
            } label: {
                Label("Share a file from here instead", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUploading)
        }
        .padding(20)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24))
        .tiltReactiveEdge(motion, cornerRadius: 24)
    }

    // Each recent-share row is its own glass card -- siblings in the same
    // GlassEffectContainer above, so they can blend/morph together as they
    // scroll near each other rather than each being an isolated effect.
    private var recentSharesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent shares")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)

            ForEach(history) { item in
                Button {
                    qrSheetItem = QRSheetItem(url: item.url, filename: item.filename)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.filename).font(.body)
                            Text(item.sharedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "qrcode")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18))
                .tiltReactiveEdge(motion, cornerRadius: 18)
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
    @State private var didCopyLink = false
    @State private var motion = TiltMotionManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 24) {
                    Text(filename)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let image = QRCodeGenerator.generate(from: urlString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 260, height: 260)
                            .padding(24)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 28))
                            .tiltReactiveEdge(motion, cornerRadius: 28)
                    }

                    Text(urlString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button {
                            copyLink()
                        } label: {
                            Label(didCopyLink ? "Copied" : "Copy Link", systemImage: didCopyLink ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.glass)

                        if let shareURL = URL(string: urlString) {
                            ShareLink(item: shareURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func copyLink() {
        UIPasteboard.general.string = urlString
        didCopyLink = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopyLink = false
        }
    }
}

#Preview {
    ContentView()
}
