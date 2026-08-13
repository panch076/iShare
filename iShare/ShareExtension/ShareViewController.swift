import UIKit
import UniformTypeIdentifiers

/// Set this as NSExtensionPrincipalClass in Info.plist (see notes there).
/// Runs entirely inside the extension process — no host-app handoff needed,
/// which keeps this simple but caps file size to whatever fits comfortably
/// in the extension's ~120MB memory budget (fine for photos/most docs;
/// see README for the App-Group handoff pattern if you need bigger files).
class ShareViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let qrImageView = UIImageView()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
        Task { await handleSharedItem() }
    }

    private func setUpUI() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "Preparing your file…"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.numberOfLines = 0

        qrImageView.contentMode = .scaleAspectFit
        qrImageView.isHidden = true

        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)
        doneButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [statusLabel, spinner, qrImageView, doneButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            qrImageView.widthAnchor.constraint(equalToConstant: 240),
            qrImageView.heightAnchor.constraint(equalToConstant: 240)
        ])

        spinner.startAnimating()
    }

    private func handleSharedItem() async {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachment = item.attachments?.first
        else {
            showError("Nothing to share.")
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

            showQRCode(for: response.url)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Pulls raw data + a filename + MIME type out of whatever the share
    /// sheet handed us (photo, PDF, video, etc). Using loadFileRepresentation
    /// (rather than loadItem for raw Data) keeps the real filename/extension.
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

    private func showQRCode(for urlString: String) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.spinner.isHidden = true
            self.statusLabel.text = "Scan to download"
            self.qrImageView.image = QRCodeGenerator.generate(from: urlString)
            self.qrImageView.isHidden = false
            self.doneButton.isHidden = false
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.spinner.isHidden = true
            self.statusLabel.text = message
            self.doneButton.isHidden = false
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
