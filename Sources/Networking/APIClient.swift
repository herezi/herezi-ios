import Domain
import Foundation

/// Errors surfaced by `APIClient`. `server` carries the contract's `Error` body when present.
public enum APIError: Error, Sendable, Equatable {
    case invalidURL
    case transport(String)
    case server(status: Int, code: String?, message: String?)
    case decoding(String)
}

/// Thin async/await HTTP client for the Herezi API. One instance per base URL.
public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Reads `HereziAPIBaseURL` from Info.plist (set per build configuration in project.yml).
    public static func baseURL(from bundle: Bundle = .main) -> URL {
        let fallback = URL(string: "http://localhost:8080")!
        guard let raw = bundle.object(forInfoDictionaryKey: "HereziAPIBaseURL") as? String,
            let url = URL(string: raw), url.scheme != nil
        else { return fallback }
        return url
    }

    func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = components.path.trimmingSuffix("/") + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder.herezi.decode(ErrorDTO.self, from: data)
            throw APIError.server(status: status, code: body?.code, message: body?.message)
        }
        do {
            return try JSONDecoder.herezi.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

extension JSONDecoder {
    /// Decoder for the contract: RFC 3339 dates with or without fractional seconds.
    public static var herezi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? Date(raw, strategy: .iso8601) { return date }
            if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected RFC 3339 date-time, got \(raw)")
        }
        return decoder
    }
}
