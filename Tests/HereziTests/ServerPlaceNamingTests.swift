import Domain
import FeatureHome
import FeatureNearby
import Foundation
import Testing

/// 위치명: 서버 역지오코딩(GET /v1/geo/reverse) 먼저, 실패·빈 값이면 OS 지오코더.
@MainActor
struct ServerPlaceNamingTests {
    private let coordinate = Coordinate.seoulCityHall

    @Test func 서버_label을_쓴다() async {
        let naming = ServerPlaceNaming(
            service: FakeSpotsService(), fallback: FixedPlaceNaming(name: "태평로1가"))
        #expect(await naming.placeName(for: coordinate) == "중구 태평로1가")
    }

    @Test func 서버가_실패하면_OS_지오코더() async {
        let naming = ServerPlaceNaming(
            service: FakeSpotsService(failure: FakeSpotsService.FakeError.notFound),
            fallback: FixedPlaceNaming(name: "태평로1가"))
        #expect(await naming.placeName(for: coordinate) == "태평로1가")
    }

    @Test func 서버가_빈_label이면_OS_지오코더() async {
        let naming = ServerPlaceNaming(
            service: StubGeoService(label: "  "), fallback: FixedPlaceNaming(name: "태평로1가"))
        #expect(await naming.placeName(for: coordinate) == "태평로1가")
    }

    @Test func 둘_다_없으면_nil() async {
        let naming = ServerPlaceNaming(
            service: FakeSpotsService(failure: FakeSpotsService.FakeError.notFound),
            fallback: FixedPlaceNaming(name: nil))
        #expect(await naming.placeName(for: coordinate) == nil)
    }

    @Test func 홈_위치명에_서버_label이_나온다() async {
        let service = FakeSpotsService(spots: TestData.spots)
        let viewModel = HomeViewModel(
            service: service, location: FixedLocationProvider(),
            naming: ServerPlaceNaming(service: service, fallback: FixedPlaceNaming(name: nil)),
            saved: makeLibrary(), now: { TestData.now })
        await viewModel.reload()
        #expect(viewModel.placeName == "중구 태평로1가")
    }
}

/// 역지오코딩 label만 정해 두는 서비스.
struct StubGeoService: SpotsService {
    let label: String

    func spots(_ query: SpotQuery) async throws -> SpotPage { SpotPage(items: []) }
    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap { SpotMap(items: [], truncated: false) }
    func spot(id: String) async throws -> Spot { throw SpotsServiceError.notFound }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> String { label }
}
