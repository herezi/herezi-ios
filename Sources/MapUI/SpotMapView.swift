import DesignSystem
import Domain
import NMapsGeometry
import NMapsMap
import SwiftUI

/// The ONLY place that touches the Naver Map SDK (enforced by scripts/check-architecture.sh).
/// Features render maps through this SwiftUI view and only see Domain types.
/// See docs/adr/0003-naver-map-sdk.md.
///
/// S2 지도 (DESIGN §6.6): 카테고리 색 원형 핀(꼬리 없음), 잉크 클러스터(숫자), 선택 핀 확대 + 제목 라벨,
/// 잉크 내 위치 점. 클러스터링은 `Domain.SpotClusterer`(화면 반경 48pt)로 카메라가 멈출 때마다 다시 한다.
public struct SpotMapView: UIViewRepresentable {
    let spots: [Spot]
    let selectedID: String?
    let camera: MapCameraTarget?
    let showsUserLocation: Bool
    let bottomInset: CGFloat
    let onSelect: @MainActor (Spot) -> Void
    let onTapMap: @MainActor () -> Void
    let onCameraIdle: @MainActor (CoordinateBounds, Bool) -> Void

    /// - Parameters:
    ///   - bottomInset: 지도 아래를 가리는 시트 높이. 보이는 영역(bbox)·로고 위치 계산에서 뺀다.
    ///   - onCameraIdle: 카메라가 멈추면 (보이는 영역, 사용자가 움직였는지).
    public init(
        spots: [Spot],
        selectedID: String? = nil,
        camera: MapCameraTarget? = nil,
        showsUserLocation: Bool = true,
        bottomInset: CGFloat = 0,
        onSelect: @escaping @MainActor (Spot) -> Void = { _ in },
        onTapMap: @escaping @MainActor () -> Void = {},
        onCameraIdle: @escaping @MainActor (CoordinateBounds, Bool) -> Void = { _, _ in }
    ) {
        self.spots = spots
        self.selectedID = selectedID
        self.camera = camera
        self.showsUserLocation = showsUserLocation
        self.bottomInset = bottomInset
        self.onSelect = onSelect
        self.onTapMap = onTapMap
        self.onCameraIdle = onCameraIdle
    }

    /// 지도 키(NCP Client ID)가 Info.plist에 들어 있는지. 없으면(개발 빌드) 화면이 대체 안내를 보여준다.
    public static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "NMFNcpKeyId") as? String ?? ""
        return !key.trimmingCharacters(in: .whitespaces).isEmpty && !key.hasPrefix("$(")
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> NMFMapView {
        let mapView = NMFMapView(frame: .zero)
        mapView.touchDelegate = context.coordinator
        mapView.addCameraDelegate(delegate: context.coordinator)
        mapView.minZoomLevel = 6
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        context.coordinator.mapView = mapView
        context.coordinator.styleLocationOverlay(on: mapView)
        if let camera {
            mapView.moveCamera(NMFCameraUpdate(scrollTo: camera.center.latLng, zoomTo: camera.zoom))
            context.coordinator.appliedCameraID = camera.id
        }
        return mapView
    }

    public func updateUIView(_ mapView: NMFMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onTapMap = onTapMap
        coordinator.onCameraIdle = onCameraIdle
        let mode: NMFMyPositionMode = showsUserLocation ? .normal : .disabled
        if mapView.positionMode != mode {
            mapView.positionMode = mode
            // 위치 추적 모드를 바꾸면 SDK가 기본 아이콘(파란 점)으로 되돌리므로 다시 입힌다.
            coordinator.styleLocationOverlay(on: mapView)
        }
        if mapView.contentInset.bottom != bottomInset {
            mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }
        if let camera, camera.id != coordinator.appliedCameraID {
            coordinator.appliedCameraID = camera.id
            let update = NMFCameraUpdate(scrollTo: camera.center.latLng, zoomTo: camera.zoom)
            update.animation = .easeIn
            update.animationDuration = 0.35
            mapView.moveCamera(update)
        }
        coordinator.update(spots: spots, selectedID: selectedID)
    }

    @MainActor
    public final class Coordinator: NSObject, NMFMapViewCameraDelegate, NMFMapViewTouchDelegate {
        weak var mapView: NMFMapView?
        var appliedCameraID: UUID?
        var onSelect: @MainActor (Spot) -> Void = { _ in }
        var onTapMap: @MainActor () -> Void = {}
        var onCameraIdle: @MainActor (CoordinateBounds, Bool) -> Void = { _, _ in }

        private var spots: [Spot] = []
        private var selectedID: String?
        /// 클러스터 id → (마커, 그린 모양 키).
        private var markers: [String: (marker: NMFMarker, style: String)] = [:]
        private var movedByUser = false
        private let images = MarkerImageCache()

        func update(spots: [Spot], selectedID: String?) {
            guard spots != self.spots || selectedID != self.selectedID else { return }
            self.spots = spots
            self.selectedID = selectedID
            recluster()
        }

        func styleLocationOverlay(on mapView: NMFMapView) {
            let overlay = mapView.locationOverlay
            overlay.icon = NMFOverlayImage(
                image: images.userDot(scale: mapView.traitCollection.displayScale), reuseIdentifier: "hz-user-dot")
            overlay.iconWidth = CGFloat(NMF_LOCATION_OVERLAY_SIZE_AUTO)
            overlay.iconHeight = CGFloat(NMF_LOCATION_OVERLAY_SIZE_AUTO)
            overlay.subIcon = nil
            overlay.circleColor = UIColor(Color.hz.ink).withAlphaComponent(0.12)
            overlay.circleOutlineWidth = 0
            overlay.circleRadius = 40
        }

        private func recluster() {
            guard let mapView else { return }
            let projection = mapView.projection
            let clusters = SpotClusterer.cluster(
                spots, excluding: selectedID.map { [$0] } ?? []
            ) { coordinate in
                let point = projection.point(from: coordinate.latLng)
                return ScreenPoint(x: point.x, y: point.y)
            }
            let scale = mapView.traitCollection.displayScale
            var next: [String: (marker: NMFMarker, style: String)] = [:]
            for cluster in clusters {
                let isSelected = cluster.isSingle && cluster.spots[0].id == selectedID
                let rendered = images.image(for: cluster, selected: isSelected, scale: scale)
                var entry = markers.removeValue(forKey: cluster.id) ?? (NMFMarker(), "")
                let marker = entry.marker
                marker.position = cluster.center.latLng
                if entry.style != rendered.key {
                    marker.iconImage = NMFOverlayImage(image: rendered.image, reuseIdentifier: rendered.key)
                    marker.width = CGFloat(NMF_MARKER_SIZE_AUTO)
                    marker.height = CGFloat(NMF_MARKER_SIZE_AUTO)
                    marker.anchor = rendered.anchor
                    entry.style = rendered.key
                }
                marker.zIndex = isSelected ? 300 : (cluster.isSingle ? 100 : 200)
                marker.isHideCollidedSymbols = isSelected
                marker.touchHandler = { [weak self] _ in
                    MainActor.assumeIsolated { self?.didTap(cluster) }
                    return true
                }
                if marker.mapView == nil { marker.mapView = mapView }
                next[cluster.id] = entry
            }
            for (_, stale) in markers { stale.marker.mapView = nil }
            markers = next
        }

        private func didTap(_ cluster: SpotCluster) {
            if cluster.isSingle {
                onSelect(cluster.spots[0])
                return
            }
            // 묶인 핀이 모두 보이게 확대 (motion.slow).
            guard let mapView else { return }
            let bounds = NMGLatLngBounds(
                southWest: cluster.bounds.southWest.latLng, northEast: cluster.bounds.northEast.latLng)
            let update = NMFCameraUpdate(fit: bounds, padding: 80)
            update.animation = .easeIn
            update.animationDuration = 0.35
            update.reason = Int32(NMFMapChangedByControl)
            mapView.moveCamera(update)
        }

        // MARK: NMFMapViewCameraDelegate

        public func mapView(_ mapView: NMFMapView, cameraWillChangeByReason reason: Int, animated: Bool) {
            if reason == NMFMapChangedByGesture || reason == NMFMapChangedByControl { movedByUser = true }
        }

        public func mapViewCameraIdle(_ mapView: NMFMapView) {
            recluster()
            let bounds = mapView.contentBounds
            let byUser = movedByUser
            movedByUser = false
            onCameraIdle(
                CoordinateBounds(southWest: bounds.southWest.coordinate, northEast: bounds.northEast.coordinate),
                byUser)
        }

        // MARK: NMFMapViewTouchDelegate

        public func mapView(_ mapView: NMFMapView, didTapMap latlng: NMGLatLng, point: CGPoint) {
            onTapMap()
        }
    }
}

/// 마커 이미지 (SwiftUI 뷰를 그려 만든다). 같은 모양은 한 번만 그린다.
@MainActor
final class MarkerImageCache {
    struct Rendered {
        let key: String
        let image: UIImage
        let anchor: CGPoint
    }

    private var cache: [String: Rendered] = [:]
    /// 그림자(elevation.1)가 잘리지 않게 둘레에 두는 여백.
    static let shadowPadding: CGFloat = 6

    func image(for cluster: SpotCluster, selected: Bool, scale: CGFloat) -> Rendered {
        if cluster.isSingle {
            let spot = cluster.spots[0]
            let title = selected ? MapPinView.label(spot.title) : ""
            let key = "pin-\(spot.category.rawValue)-\(selected)-\(title)"
            return render(key: key, scale: scale, pinCenterFromTop: selected ? 22 : 18) {
                MapPinView(category: spot.category, title: selected ? title : nil)
            }
        }
        let key = "cluster-\(cluster.countLabel)-\(cluster.diameter)"
        return render(key: key, scale: scale, pinCenterFromTop: cluster.diameter / 2) {
            MapClusterView(label: cluster.countLabel, diameter: cluster.diameter)
        }
    }

    func userDot(scale: CGFloat) -> UIImage {
        render(key: "user-dot", scale: scale, pinCenterFromTop: 10) {
            Circle()
                .fill(Color.hz.ink)
                .frame(width: 14, height: 14)
                .padding(3)
                .background(Circle().fill(Color.white))
        }.image
    }

    /// `pinCenterFromTop`: 그린 뷰 맨 위에서 원 중심까지(여백 제외). 앵커를 원 중심에 맞춘다.
    private func render(
        key: String, scale: CGFloat, pinCenterFromTop: CGFloat, @ViewBuilder content: () -> some View
    ) -> Rendered {
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: content().padding(Self.shadowPadding))
        renderer.scale = scale
        let image = renderer.uiImage ?? UIImage()
        let size = image.size
        let anchor =
            size.height > 0
            ? CGPoint(x: 0.5, y: (Self.shadowPadding + pinCenterFromTop) / size.height)
            : CGPoint(x: 0.5, y: 0.5)
        let rendered = Rendered(key: key, image: image, anchor: anchor)
        cache[key] = rendered
        return rendered
    }
}

/// 핀 (DESIGN §6.6): 지름 36 카테고리 색 원, 흰 테두리 2, 흰 아이콘 18, elevation.1.
/// 선택되면(`title` 있음) 지름 44, 잉크 테두리 3, 아래 6 간격에 제목 알약.
struct MapPinView: View {
    let category: SpotCategory
    let title: String?

    /// 제목 라벨: 최대 12자, 넘치면 말줄임.
    static func label(_ title: String) -> String {
        title.count > 12 ? String(title.prefix(11)) + "…" : title
    }

    var body: some View {
        let selected = title != nil
        let diameter: CGFloat = selected ? 44 : HZSize.pin
        VStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .font(.system(size: selected ? 21 : 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(category.color))
                .overlay(Circle().strokeBorder(selected ? Color.hz.ink : .white, lineWidth: selected ? 3 : 2))
                .hzElevation(.level1)
            if let title {
                Text(title)
                    .font(HZFontFamily.font(fixedSize: 13, weight: .semibold))
                    .foregroundStyle(Color.hz.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.white))
                    .hzElevation(.level1)
            }
        }
        .environment(\.colorScheme, .light)
    }
}

/// 클러스터 (DESIGN §6.6): 잉크 원 + 흰 숫자(13 Bold, 고정폭), 흰 테두리 2.
struct MapClusterView: View {
    let label: String
    let diameter: Double

    var body: some View {
        Text(label)
            .font(HZFontFamily.font(fixedSize: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.hz.ink))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .hzElevation(.level1)
    }
}

extension Coordinate {
    fileprivate var latLng: NMGLatLng {
        NMGLatLng(lat: latitude, lng: longitude)
    }
}

extension NMGLatLng {
    fileprivate var coordinate: Coordinate {
        Coordinate(latitude: lat, longitude: lng)
    }
}
