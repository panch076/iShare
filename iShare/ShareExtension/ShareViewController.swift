import SwiftUI
import UniformTypeIdentifiers
import Observation

// MARK: - View Model

@Observable
@MainActor
final class ShareExtensionViewModel {
    enum Status {
        case loading
        case success(url: String, filename: String)
        case failure(String)
    }

    var status: Status = .loading

    func start(with context: NSExtensionContext) async {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let attachment = item.attachments?.first
        else {
            status = .failure("Nothing to share.")
            return
        }

        do {
            let (data, filename, mimeType) = try await loadFile(from: attachment)
            let response = try await UploadManager.shared.upload(fileData: data, filename: filename, mimeType: mimeType)
            ShareHistoryStore.add(SharedFile(
                id: response.id,
                filename: filename,
                url: response.url,
                expiresAt: response.expiresAt,
                sharedAt: Date()
            ))
            status = .success(url: response.url, filename: filename)
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private func loadFile(from provider: NSItemProvider) async throws -> (Data, String, String) {
        let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url, let data = try? Data(contentsOf: url) else {
                    continuation.resume(throwing: UploadError.noData)
                    return
                }
                let filename = url.lastPathComponent
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                continuation.resume(returning: (data, filename, mimeType))
            }
        }
    }
}

// MARK: - SwiftUI View

struct ShareExtensionView: View {
    var model: ShareExtensionViewModel
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 0) {
                    switch model.status {
                    case .loading:
                        loadingCard
                    case .success(let url, let filename):
                        successCard(url: url, filename: filename)
                    case .failure(let message):
                        errorCard(message: message)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var loadingCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.85))
                .symbolRenderingMode(.hierarchical)

            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)

            VStack(spacing: 6) {
                Text("Uploading your file…")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Hang tight while we make it shareable.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 28))
    }

    private func successCard(url: String, filename: String) -> some View {
        VStack(spacing: 20) {
            Text(filename)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            if let image = QRCodeGenerator.generate(from: url) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20))
            }

            Text("Scan to download")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            Text(url)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button("Done") { onFinish() }
                .buttonStyle(.glass)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 28))
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
                .symbolRenderingMode(.hierarchical)

            Text("Something went wrong")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Dismiss") { onFinish() }
                .buttonStyle(.glass)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - View Controller

class ShareViewController: UIViewController {
    private let model = ShareExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let swiftUIView = ShareExtensionView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }

        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        guard let context = extensionContext else {
            model.status = .failure("No extension context.")
            return
        }
        Task { await model.start(with: context) }
    }
}
