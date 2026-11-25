import Domain
import Foundation
import Testing

@MainActor
struct SavedLibraryTests {
    private var spots: [Spot] { TestData.spots }

    @Test func 로그인_전_저장은_로그인_시트를_띄우고_채우지_않는다() async {
        let library = makeLibrary(provider: nil)
        let message = await library.toggle(spots[0])

        #expect(message == nil)
        #expect(!library.isSaved(spots[0].id))
        #expect(library.auth.loginRequest?.purpose == .save)
    }

    @Test func 로그인하면_대기_중_저장을_마치고_토스트를_차례로() async throws {
        let account = ScriptedAccountService()
        let library = makeLibrary(provider: nil, account: account, legacy: [spots[1], spots[2]])
        _ = await library.toggle(spots[0])
        let request = try #require(library.auth.loginRequest)

        try await library.auth.signIn(provider: .kakao, idToken: "t", nonce: nil)
        let messages = await library.completeLogin(request)

        #expect(messages == ["저장했어요", "기기에 저장했던 2개를 계정으로 옮겼어요"])
        #expect(library.isSaved(spots[0].id) && library.isSaved(spots[1].id) && library.isSaved(spots[2].id))
        // 옮기기는 saved:import 한 번, 성공하면 기기 로컬 저장을 지운다.
        let calls = await account.importCalls
        #expect(calls.count == 1)
        #expect(Set(calls[0]) == [spots[1].id, spots[2].id])
        #expect(library.legacyCount == 0)
    }

    @Test func 로그인_행에서_로그인하면_로그인했어요() async throws {
        let library = makeLibrary(provider: nil)
        library.auth.requestLogin(.account)
        let request = try #require(library.auth.loginRequest)
        try await library.auth.signIn(provider: .apple, idToken: "t", nonce: "n")
        #expect(await library.completeLogin(request) == ["로그인했어요"])
    }

    @Test func 이미_계정에_있는_항목은_옮긴_수에서_빠진다() async {
        let account = FakeAccountService(spots: TestData.spots, savedIDs: [TestData.spots[0].id], now: { TestData.now })
        let library = makeLibrary(account: account, legacy: [spots[0], spots[1]])
        #expect(await library.migrateLegacy() == 1)
        #expect(library.legacyCount == 0)
    }

    @Test func 저장_실패는_되돌리고_다시_눌러_달라고_한다() async {
        let account = ScriptedAccountService()
        await account.set(save: AuthError.unavailable)
        let library = makeLibrary(account: account)

        let message = await library.toggle(spots[0])

        #expect(message == "저장하지 못했어요. 다시 눌러 주세요.")
        #expect(!library.isSaved(spots[0].id))
        #expect(library.auth.isLoggedIn)  // 503은 로그아웃하지 않는다
    }

    @Test func 저장_한도_초과_토스트() async {
        let account = ScriptedAccountService()
        await account.set(save: AccountError.savedLimitExceeded)
        let library = makeLibrary(account: account)
        #expect(await library.toggle(spots[0]) == "저장은 500개까지 할 수 있어요. 안 보는 볼거리를 지워 주세요.")
    }

    @Test func 저장하고_취소한다() async {
        let library = makeLibrary()
        #expect(await library.toggle(spots[0]) == "저장했어요")
        #expect(library.items.first?.savedAt == TestData.now)
        #expect(await library.toggle(spots[0]) == "저장을 취소했어요")
        #expect(library.items.isEmpty)
    }

    @Test func 지우기_실패는_되돌린다() async throws {
        let account = ScriptedAccountService()
        let library = makeLibrary(account: account)
        _ = await library.save(spots[0])
        await account.set(unsave: AccountError.offline)

        await #expect(throws: AccountError.offline) { try await library.remove(ids: [spots[0].id]) }
        #expect(library.isSaved(spots[0].id))
    }

    @Test func 목록은_계정별로_캐시한다() async throws {
        let defaults = freshDefaults()
        let account = FakeAccountService(
            spots: TestData.spots, savedIDs: ["sample-1", "sample-2"], now: { TestData.now })
        let library = makeLibrary(account: account, defaults: defaults)
        try await library.refresh()
        #expect(library.items.map(\.id) == ["sample-1", "sample-2"])
        #expect(library.state == .loaded)

        // 다시 열면 캐시로 바로 그린다.
        let reopened = makeLibrary(account: ScriptedAccountService(), defaults: defaults)
        #expect(reopened.items.map(\.id) == ["sample-1", "sample-2"])
    }

    @Test func 로그아웃하면_목록과_캐시를_지운다() async throws {
        let defaults = freshDefaults()
        let account = FakeAccountService(spots: TestData.spots, savedIDs: ["sample-1"], now: { TestData.now })
        let library = makeLibrary(account: account, defaults: defaults)
        try await library.refresh()

        let kakao = FakeKakaoLogin()
        await AccountActions(library: library, account: account, kakao: kakao, apple: FakeAppleReauth()).signOut()

        #expect(!library.isLoggedIn)
        #expect(library.items.isEmpty)
        #expect(kakao.logoutCount == 1)
        #expect(makeLibrary(account: account, defaults: defaults).items.isEmpty)
    }

    @Test func 세션_만료면_로그아웃_상태와_다시_로그인_문구() async {
        let account = ScriptedAccountService()
        await account.set(save: AuthError.unauthorized)
        // 가짜 백엔드의 리프레시는 성공하지만 다시 401 → 만료.
        let library = makeLibrary(account: account)
        #expect(await library.toggle(spots[0]) == "다시 로그인해 주세요")
        #expect(!library.isLoggedIn)
    }

    @Test func 탈퇴하면_카카오_연결을_끊고_모두_지운다() async throws {
        let account = ScriptedAccountService()
        let library = makeLibrary(account: account, legacy: [spots[3]])
        _ = await library.save(spots[0])
        let kakao = FakeKakaoLogin()

        try await AccountActions(library: library, account: account, kakao: kakao, apple: FakeAppleReauth())
            .deleteAccount()

        #expect(kakao.unlinkCount == 1)
        #expect(await account.deleteCalls == 1)
        #expect(!library.isLoggedIn)
        #expect(library.items.isEmpty)
        #expect(library.legacyCount == 0)
    }

    @Test func Apple_탈퇴는_재인증_코드를_보내고_카카오_연결끊기는_안_한다() async throws {
        let account = ScriptedAccountService()
        let library = makeLibrary(provider: .apple, account: account)
        let kakao = FakeKakaoLogin()
        let apple = FakeAppleReauth(result: .success("apple-code"))

        try await AccountActions(library: library, account: account, kakao: kakao, apple: apple).deleteAccount()

        #expect(apple.requestCount == 1)
        #expect(kakao.unlinkCount == 0)
        #expect(await account.deleteAppleCodes == ["apple-code"])
        #expect(!library.isLoggedIn)
    }

    @Test func 카카오_탈퇴는_Apple_재인증_없이_코드_없음() async throws {
        let account = ScriptedAccountService()
        let library = makeLibrary(provider: .kakao, account: account)
        let apple = FakeAppleReauth()

        try await AccountActions(library: library, account: account, kakao: FakeKakaoLogin(), apple: apple)
            .deleteAccount()

        #expect(apple.requestCount == 0)
        #expect(await account.deleteAppleCodes == [nil])
    }

    @Test func Apple_재인증을_취소하면_서버를_부르지_않고_아무것도_지우지_않는다() async {
        let account = ScriptedAccountService()
        let library = makeLibrary(provider: .apple, account: account)
        _ = await library.save(spots[0])
        let apple = FakeAppleReauth(result: .failure(.cancelled))

        await #expect(throws: AuthError.cancelled) {
            try await AccountActions(library: library, account: account, kakao: FakeKakaoLogin(), apple: apple)
                .deleteAccount()
        }
        #expect(await account.deleteCalls == 0)
        #expect(library.isLoggedIn)
        #expect(library.isSaved(spots[0].id))
    }

    @Test func 탈퇴_실패면_아무것도_지우지_않는다() async {
        let account = ScriptedAccountService()
        await account.set(delete: AccountError.server)
        let library = makeLibrary(account: account)
        _ = await library.save(spots[0])

        await #expect(throws: AccountError.server) {
            try await AccountActions(
                library: library, account: account, kakao: FakeKakaoLogin(), apple: FakeAppleReauth()
            ).deleteAccount()
        }
        #expect(library.isLoggedIn)
        #expect(library.isSaved(spots[0].id))
    }
}
