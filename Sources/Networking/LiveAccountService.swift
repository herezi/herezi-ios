import Domain
import Foundation

/// `AccountService` — 로그인 사용자 API (`/v1/me/saved`, `/v1/me/saved/{spot_id}`, `/v1/me/saved:import`, `/v1/me`).
/// 모든 요청에 `Authorization: Bearer <Supabase access token>`을 붙인다.
public struct LiveAccountService: AccountService {
    private let client: APIClient
    private let now: @Sendable () -> Date

    public init(client: APIClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    public func savedPage(cursor: String?, accessToken: String) async throws -> SavedPage {
        var query = [URLQueryItem(name: "limit", value: String(SavedLibrary.pageLimit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await mapped {
            try await client.get(SpotPageDTO.self, path: "/v1/me/saved", query: query, bearer: accessToken)
        }
        return dto.toSavedPage(fallbackDate: now())
    }

    public func save(spotID: String, accessToken: String) async throws {
        try await mapped {
            try await client.send("PUT", path: "/v1/me/saved/\(APIClient.pathSegment(spotID))", bearer: accessToken)
        }
    }

    public func unsave(spotID: String, accessToken: String) async throws {
        try await mapped {
            try await client.send("DELETE", path: "/v1/me/saved/\(APIClient.pathSegment(spotID))", bearer: accessToken)
        }
    }

    public func importSaved(spotIDs: [String], accessToken: String) async throws -> SavedImportResult {
        let body = try JSONEncoder().encode(SavedImportRequestDTO(spotIDs: spotIDs))
        let data = try await mapped {
            try await client.send("POST", path: "/v1/me/saved:import", bearer: accessToken, body: body)
        }
        do {
            let dto = try JSONDecoder.herezi.decode(SavedImportResultDTO.self, from: data)
            return SavedImportResult(imported: dto.imported, skippedUnknown: dto.skippedUnknown)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    public func deleteAccount(accessToken: String, appleAuthorizationCode: String?) async throws {
        let body = try appleAuthorizationCode.map {
            try JSONEncoder().encode(DeleteMeRequestDTO(appleAuthorizationCode: $0))
        }
        try await mapped { try await client.send("DELETE", path: "/v1/me", bearer: accessToken, body: body) }
    }

    /// HTTP 오류 → 도메인 오류. 401 → `AuthError.unauthorized`(리프레시 후 재시도), 503 → `AuthError.unavailable`
    /// (로그아웃하지 않음), 400 `apple_reauth_required` → `AccountError.appleReauthRequired`, 409 `saved_limit_exceeded` → `AccountError.savedLimitExceeded`, 404 → `notFound`.
    @discardableResult
    private func mapped<T>(_ request: () async throws -> T) async throws -> T {
        do {
            return try await request()
        } catch let error as APIError {
            throw Self.domainError(error)
        }
    }

    static func domainError(_ error: APIError) -> any Error {
        switch error {
        case .server(status: 401, _, _): AuthError.unauthorized
        case .server(status: 503, _, _): AuthError.unavailable
        case .server(status: 409, _, _): AccountError.savedLimitExceeded
        case .server(status: 400, "apple_reauth_required", _): AccountError.appleReauthRequired
        case .server(status: 404, _, _): AccountError.notFound
        case .transport: AccountError.offline
        case .server, .invalidURL, .decoding: AccountError.server
        }
    }
}
