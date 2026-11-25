import Foundation

/// 근처 목록·검색 조회 조건. 기기 안에서 지역 데이터로 계산한다(`SpotQueryEngine.nearby`) — 서버로 보내지 않는다(#37).
public struct SpotQuery: Hashable, Sendable {
    public var coordinate: Coordinate
    public var radiusMeters: Int
    /// Empty set means "all categories".
    public var categories: Set<SpotCategory>
    public var when: WhenFilter
    /// 무료 항목만.
    public var freeOnly: Bool
    /// 키워드(제목·장소명·주소, 대소문자 무시 부분 일치). 앞뒤 공백을 자른 뒤 비어 있으면 거르지 않는다.
    public var keyword: String?
    /// 다음 페이지 위치(엔진이 준 `nextCursor`).
    public var cursor: String?
    public var limit: Int

    /// 키워드 최대 글자 수(서버 `q` 규칙과 같음).
    public static let keywordMaxLength = 50

    public init(
        coordinate: Coordinate,
        radiusMeters: Int = 3000,
        categories: Set<SpotCategory> = [],
        when: WhenFilter = .now,
        freeOnly: Bool = false,
        keyword: String? = nil,
        cursor: String? = nil,
        limit: Int = 30
    ) {
        self.coordinate = coordinate
        self.radiusMeters = radiusMeters
        self.categories = categories
        self.when = when
        self.freeOnly = freeOnly
        self.keyword = keyword
        self.cursor = cursor
        self.limit = limit
    }

    /// 거를 키워드. 앞뒤 공백을 자르고 50자로 자른다. 비면 nil.
    public var normalizedKeyword: String? {
        guard let trimmed = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(Self.keywordMaxLength))
    }
}

/// 지도 영역 조회 조건. 기기 안에서 계산한다(`SpotQueryEngine.inBounds`). 클러스터링도 앱에서 한다.
public struct SpotMapQuery: Hashable, Sendable {
    public var bounds: CoordinateBounds
    /// Empty set means "all categories".
    public var categories: Set<SpotCategory>
    public var when: WhenFilter
    /// 무료 항목만.
    public var freeOnly: Bool
    /// 최대 개수(S2: 200). 넘치면 `truncated`.
    public var limit: Int

    public init(
        bounds: CoordinateBounds,
        categories: Set<SpotCategory> = [],
        when: WhenFilter = .now,
        freeOnly: Bool = false,
        limit: Int = 200
    ) {
        self.bounds = bounds
        self.categories = categories
        self.when = when
        self.freeOnly = freeOnly
        self.limit = limit
    }
}

/// Port: where spots come from. 앱은 `LocalSpotsService`(지역 데이터 + 기기 계산, #37), 미리보기·테스트는
/// `FakeSpotsService`. Features depend on this protocol only. 사용자 좌표는 이 포트 밖(서버)으로 나가지 않는다.
public protocol SpotsService: Sendable {
    func spots(_ query: SpotQuery) async throws -> SpotPage
    /// 지도 영역(bbox) 안의 항목. 영역 중심에서 가까운 순, 끝난 항목은 없다.
    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap
    /// 상세. 끝난 항목도 반환한다(`isEnded == true`).
    func spot(id: String) async throws -> Spot
    /// 기기 데이터를 서버와 맞춘다(지역 파일 `If-None-Match`). 새 데이터를 받았으면 true.
    /// `force == false`면 최근에 확인했을 때 요청하지 않는다. 받지 못하면 던지지만 기존 데이터는 그대로 쓸 수 있다.
    func refreshData(force: Bool) async throws -> Bool
}

extension SpotsService {
    /// 동기화할 데이터가 없는 구현(가짜 서비스 등)은 아무것도 하지 않는다.
    public func refreshData(force: Bool) async throws -> Bool { false }
}

/// 포트가 던지는 도메인 오류. 어댑터(HTTP 등)는 자기 오류를 이것으로 바꿔 Features가 구분할 수 있게 한다.
public enum SpotsServiceError: Error, Sendable, Equatable {
    /// 상세 404 — 끝났거나 없는 항목.
    case notFound
}

/// 위치 권한 상태 (S0·S6).
public enum LocationPermission: Sendable, Equatable {
    /// 아직 한 번도 묻지 않음.
    case notDetermined
    /// 정확한 위치 허용.
    case authorized
    /// 대략적 위치만 허용.
    case approximate
    /// 거부 또는 제한.
    case denied

    /// 위치를 쓸 수 있는지.
    public var isGranted: Bool { self == .authorized || self == .approximate }
}

/// Port: 위치 권한 상태 조회·요청. App 레이어가 CoreLocation으로 구현한다.
@MainActor
public protocol LocationPermissionProviding: AnyObject {
    var permission: LocationPermission { get }
    /// 시스템 권한 창을 띄우고 사용자가 고른 결과를 돌려준다. 이미 정해졌으면 바로 현재 상태.
    func requestWhenInUse() async -> LocationPermission
}

/// Port: 좌표 → 짧은 위치명("중구 태평로1가"). App 레이어가 기기 지오코더(CLGeocoder)로 구현한다 — 서버로 보내지 않는다. 실패하면 nil.
@MainActor
public protocol PlaceNaming {
    func placeName(for coordinate: Coordinate) async -> String?
}

/// Port: the user's current location. Implemented in the App layer with CoreLocation.
@MainActor
public protocol LocationProviding {
    func currentCoordinate() async throws -> Coordinate
}
