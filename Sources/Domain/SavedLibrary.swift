import Foundation
import Observation

/// 계정 저장 목록 (S4·S7, TECH-PLAN §4.1). 저장은 계정에 하고, 마지막 응답을 계정별로 기기에 캐시한다.
///
/// - 로그인 전에는 비어 있다. 저장을 누르면 로그인 시트(S7)를 띄우고 로그인 뒤 저장한다(`toggle`).
/// - 저장·삭제는 낙관적 갱신: 먼저 바꾸고 요청, 실패하면 되돌린다.
/// - `legacy`는 v1.3 이전 앱이 기기에만 저장한 목록. 첫 로그인 때 `POST /v1/me/saved:import` 한 번으로 옮기고 지운다.
@MainActor
@Observable
public final class SavedLibrary {
    public enum LoadState: Equatable, Sendable {
        /// 아직 안 받음(로그아웃 포함).
        case idle
        case loading
        case loaded
        /// 마지막 조회 실패(캐시가 있으면 캐시를 그대로 보여준다).
        case failed
    }

    /// `saved:import` 한 번에 보낼 수 있는 최대 개수(계약).
    public nonisolated static let importLimit = 200
    /// `GET /v1/me/saved` 페이지 크기(계약 최대 100).
    public nonisolated static let pageLimit = 100
    /// 동시에 보내는 삭제 요청 수.
    public nonisolated static let concurrency = 4

    /// 로그인 사용자의 저장 목록, 저장 시각 최신순.
    public private(set) var items: [SavedSpot] = []
    public private(set) var state: LoadState = .idle
    /// 첫 로그인 옮기기 중(S4 스켈레톤).
    public private(set) var isMigrating = false

    public let auth: AuthService
    /// 기기 로컬 저장(v1.3 이전). 로그인 전 S4가 개수만 안내한다.
    public let legacy: SavedSpotsStore
    private let account: any AccountService
    private let cache: UserDefaults
    private let now: @Sendable () -> Date

    public init(
        auth: AuthService, account: any AccountService, legacy: SavedSpotsStore, cache: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.auth = auth
        self.account = account
        self.legacy = legacy
        self.cache = cache
        self.now = now
        load(for: auth.session?.userID)
        auth.observeSession { [weak self] session in self?.load(for: session?.userID) }
    }

    public var isLoggedIn: Bool { auth.isLoggedIn }
    public var legacyCount: Int { legacy.items.count }

    public func isSaved(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    // MARK: 목록

    /// `GET /v1/me/saved`를 끝까지 받아 바꾸고 캐시한다. 실패하면 던지고 기존 목록은 그대로 둔다.
    public func refresh() async throws {
        guard let userID = auth.session?.userID else { return }
        if items.isEmpty { state = .loading }
        do {
            var all: [SavedSpot] = []
            var cursor: String?
            let account = self.account
            repeat {
                let page = try await auth.authorized { [cursor] token in
                    try await account.savedPage(cursor: cursor, accessToken: token)
                }
                all += page.items
                cursor = page.nextCursor
            } while cursor != nil
            guard auth.session?.userID == userID else { return }
            items = all
            state = .loaded
            persist()
        } catch {
            if auth.session?.userID == userID { state = .failed }
            throw error
        }
    }

    // MARK: 저장 · 취소

    /// 저장 버튼(S3 상단 바, 홈 히어로, 길게 누르기 메뉴). 로그인 전이면 로그인 시트를 띄우고 로그인 뒤 저장한다.
    /// 돌려주는 문구를 토스트로 보여준다(로그인 시트를 띄웠으면 nil — 아이콘은 채우지 않는다).
    public func toggle(_ spot: Spot) async -> String? {
        guard auth.isLoggedIn else {
            auth.requestLogin(.save) { [weak self] in await self?.save(spot) }
            return nil
        }
        if isSaved(spot.id) {
            do {
                try await remove(ids: [spot.id])
                return "저장을 취소했어요"
            } catch {
                return Self.message(for: error, fallback: "저장하지 못했어요. 다시 눌러 주세요.")
            }
        }
        return await save(spot)
    }

    /// 저장(`PUT /v1/me/saved/{id}`, 낙관적). 문구를 돌려준다.
    public func save(_ spot: Spot) async -> String {
        guard !isSaved(spot.id) else { return "저장했어요" }
        items.insert(SavedSpot(spot: spot, savedAt: now()), at: 0)
        persist()
        let account = self.account
        do {
            try await auth.authorized { try await account.save(spotID: spot.id, accessToken: $0) }
            return "저장했어요"
        } catch {
            items.removeAll { $0.id == spot.id }
            persist()
            return Self.message(for: error, fallback: "저장하지 못했어요. 다시 눌러 주세요.")
        }
    }

    /// 지우기(`DELETE /v1/me/saved/{id}`, 낙관적). 지운 항목을 돌려준다(되돌리기용).
    /// 하나라도 실패하면 실패한 항목을 되돌리고 던진다.
    @discardableResult
    public func remove(ids: Set<String>) async throws -> [SavedSpot] {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        items.removeAll { ids.contains($0.id) }
        persist()
        var failed: [SavedSpot] = []
        var firstError: (any Error)?
        for batch in removed.chunked(into: Self.concurrency) {
            let outcomes = await withTaskGroup(of: (SavedSpot, (any Error)?).self) { group in
                for saved in batch {
                    group.addTask { [self] in
                        do {
                            try await self.unsave(saved.id)
                            return (saved, nil)
                        } catch {
                            return (saved, error)
                        }
                    }
                }
                var collected: [(SavedSpot, (any Error)?)] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }
            for (saved, error) in outcomes {
                if let error {
                    failed.append(saved)
                    if firstError == nil { firstError = error }
                }
            }
        }
        if let firstError {
            insert(failed)
            throw firstError
        }
        return removed
    }

    /// 되돌리기: 지웠던 항목을 원래 저장 시각으로 다시 넣고 `PUT`.
    public func restore(_ saved: [SavedSpot]) async throws {
        let new = saved.filter { !isSaved($0.id) }
        guard !new.isEmpty else { return }
        insert(new)
        let account = self.account
        for entry in new {
            do {
                try await auth.authorized { try await account.save(spotID: entry.id, accessToken: $0) }
            } catch {
                items.removeAll { $0.id == entry.id }
                persist()
                throw error
            }
        }
    }

    private func unsave(_ id: String) async throws {
        let account = self.account
        try await auth.authorized { try await account.unsave(spotID: id, accessToken: $0) }
    }

    private func insert(_ saved: [SavedSpot]) {
        items = (items + saved.filter { entry in !items.contains { $0.id == entry.id } })
            .sorted { $0.savedAt > $1.savedAt }
        persist()
    }

    // MARK: 로그인 · 옮기기

    /// 기기 로컬 저장을 계정으로 옮긴다(`POST /v1/me/saved:import`, 200개씩 — 보통 한 번). 성공한 묶음만 로컬에서 지운다.
    /// 실패하면 남겨 두고 다음 실행 때 조용히 다시 한다. 새로 옮긴 수를 돌려준다.
    public func migrateLegacy() async -> Int {
        let ids = legacy.items.map(\.id)
        guard auth.isLoggedIn, !ids.isEmpty else { return 0 }
        isMigrating = true
        defer { isMigrating = false }
        var imported = 0
        let account = self.account
        for chunk in ids.chunked(into: Self.importLimit) {
            do {
                let result = try await auth.authorized {
                    try await account.importSaved(spotIDs: chunk, accessToken: $0)
                }
                imported += result.imported
                legacy.remove(ids: Set(chunk))
            } catch {
                break
            }
        }
        return imported
    }

    /// 로그인 직후 순서(S7 "로그인 후 처리"): 기기 저장 옮기기 → 목록 받기 → 대기 동작(저장) → 토스트 문구들.
    /// 문구는 차례대로 보여준다: "저장했어요"(또는 "로그인했어요") → "기기에 저장했던 N개를 계정으로 옮겼어요".
    public func completeLogin(_ request: LoginRequest) async -> [String] {
        let moved = await migrateLegacy()
        try? await refresh()
        var messages: [String] = []
        if let action = request.action {
            if let message = await action() { messages.append(message) }
        } else {
            messages.append("로그인했어요")
        }
        if moved > 0 { messages.append("기기에 저장했던 \(moved)개를 계정으로 옮겼어요") }
        return messages
    }

    /// 앱 시작: 로그인 상태면 남은 기기 저장을 조용히 옮기고 목록을 갱신한다.
    public func start() async {
        guard auth.isLoggedIn else { return }
        _ = await migrateLegacy()
        try? await refresh()
    }

    /// 로그아웃·탈퇴: 이 계정의 캐시를 지운다. 탈퇴면 기기 로컬 저장도 지운다.
    public func clearLocalData(includingLegacy: Bool = false) {
        if let userID = auth.session?.userID { cache.removeObject(forKey: Self.cacheKey(userID)) }
        items = []
        state = .idle
        if includingLegacy { legacy.remove(ids: Set(legacy.items.map(\.id))) }
    }

    // MARK: 캐시

    static func cacheKey(_ userID: String) -> String { "herezi.accountSaved.v1.\(userID)" }

    private func load(for userID: String?) {
        state = .idle
        guard let userID,
            let data = cache.data(forKey: Self.cacheKey(userID)),
            let decoded = try? JSONDecoder().decode([SavedSpot].self, from: data)
        else {
            items = []
            return
        }
        items = decoded.sorted { $0.savedAt > $1.savedAt }
    }

    private func persist() {
        guard let userID = auth.session?.userID, let data = try? JSONEncoder().encode(items) else { return }
        cache.set(data, forKey: Self.cacheKey(userID))
    }

    // MARK: 문구

    /// 저장 실패 토스트. 세션 만료·한도·오프라인은 따로, 나머지(503 포함)는 `fallback`("다시 눌러 주세요").
    public static func message(for error: any Error, fallback: String) -> String {
        switch error {
        case AuthError.sessionExpired, AuthError.notLoggedIn: "다시 로그인해 주세요"
        case AccountError.savedLimitExceeded: "저장은 500개까지 할 수 있어요. 안 보는 볼거리를 지워 주세요."
        case AccountError.offline, AuthError.offline: "인터넷 연결을 확인하고 다시 시도해 주세요."
        default: fallback
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension SavedLibrary {
    /// 미리보기용: 가짜 인증·메모리 계정 API. `provider`가 있으면 로그인 상태로 시작한다.
    public static func preview(provider: AuthProvider? = nil, savedIDs: [String] = []) -> SavedLibrary {
        let suite = "herezi.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let auth = AuthService(
            backend: FakeAuthBackend(),
            storage: InMemorySessionStore(provider.map { FakeAuthBackend.session(provider: $0) }))
        return SavedLibrary(
            auth: auth, account: FakeAccountService(savedIDs: savedIDs),
            legacy: SavedSpotsStore(defaults: defaults, key: "legacy"), cache: defaults)
    }
}
