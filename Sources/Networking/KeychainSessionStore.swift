import Domain
import Foundation
import Security

/// 로그인 세션을 키체인(generic password)에 JSON으로 둔다. 이 기기에서만, 첫 잠금 해제 후 읽을 수 있다.
public struct KeychainSessionStore: SessionStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.herezi.app.auth", account: String = "supabase-session") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// 키체인은 앱을 지워도 남는다. 새로 설치한 뒤 처음 실행이면 이전 설치의 세션을 지운다(로그인 전 상태로 시작).
    public func clearIfFreshInstall(defaults: UserDefaults = .standard) {
        let key = "herezi.keychainInitialized.v1"
        guard !defaults.bool(forKey: key) else { return }
        clear()
        defaults.set(true, forKey: key)
    }
}
