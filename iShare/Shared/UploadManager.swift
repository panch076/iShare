import Foundation

struct UploadResponse: Decodable {
    let id: String
    let url: String
    let expiresAt: String
}

enum UploadError: LocalizedError {
    case noData
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noData: return "Couldn't read the shared file."
        case .serverError(let message): return message
        case .invalidResponse: return "The server sent back something unexpected."
        }
    }
}

/// Uploads a single file to the relay server as multipart/form-data
/// and returns the info needed to build a QR code.
final class UploadManager {
    static let shared = UploadManager()
    private init() {}

    func upload(fileData: Data, filename: String, mimeType: String) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: RelayConfig.baseURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Upload failed (\(http.statusCode))"
            throw UploadError.serverError(message)
        }

        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }
}
