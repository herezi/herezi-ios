import Domain
import NMapsGeometry
import NMapsMap
import SwiftUI

/// The ONLY place that touches the Naver Map SDK (enforced by scripts/check-architecture.sh).
/// Features render maps through this SwiftUI view and only see Domain types.
/// See docs/adr/0003-naver-map-sdk.md.
public struct SpotMapView: UIViewRepresentable {
    let spots: [Spot]
    let center: Coordinate
    let zoom: Double
    let showsUserLocation: Bool
    let onSelect: @MainActor (Spot) -> Void

    public init(
        spots: [Spot],
        center: Coordinate,
        zoom: Double = 14,
        showsUserLocation: Bool = true,
        onSelect: @escaping @MainActor (Spot) -> Void = { _ in }
    ) {
        self.spots = spots
        self.center = center
        self.zoom = zoom
        self.showsUserLocation = showsUserLocation
        self.onSelect = onSelect
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)
        view.showLocationButton = showsUserLocation
        view.showZoomControls = false
        view.mapView.positionMode = showsUserLocation ? .normal : .disabled
        view.mapView.moveCamera(NMFCameraUpdate(scrollTo: center.latLng, zoomTo: zoom))
        return view
    }

    public func updateUIView(_ view: NMFNaverMapView, context: Context) {
        context.coordinator.render(spots, on: view.mapView, onSelect: onSelect)
    }

    @MainActor
    public final class Coordinator {
        private var markers: [String: NMFMarker] = [:]

        func render(_ spots: [Spot], on mapView: NMFMapView, onSelect: @escaping @MainActor (Spot) -> Void) {
            let ids = Set(spots.map(\.id))
            for (id, marker) in markers where !ids.contains(id) {
                marker.mapView = nil
                markers[id] = nil
            }
            for spot in spots {
                let marker = markers[spot.id] ?? NMFMarker()
                marker.position = spot.coordinate.latLng
                marker.captionText = spot.title
                marker.touchHandler = { _ in
                    MainActor.assumeIsolated { onSelect(spot) }
                    return true
                }
                marker.mapView = mapView
                markers[spot.id] = marker
            }
        }
    }
}

extension Coordinate {
    fileprivate var latLng: NMGLatLng {
        NMGLatLng(lat: latitude, lng: longitude)
    }
}
