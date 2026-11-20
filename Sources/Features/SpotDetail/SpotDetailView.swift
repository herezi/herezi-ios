import Domain
import MapUI
import SwiftUI

/// Detail for one spot. Pure presentation of a `Spot` value; no networking.
public struct SpotDetailView: View {
    let spot: Spot

    public init(spot: Spot) {
        self.spot = spot
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let summary = spot.summary {
                    Text(summary)
                        .font(.body)
                }
                infoRows
                map
                if let sourceURL = spot.sourceURL {
                    Link(destination: sourceURL) {
                        Label("원문 보기", systemImage: "safari")
                    }
                }
                Text("출처: \(spot.source)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(spot.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(spot.category.displayName, systemImage: spot.category.symbolName)
                .font(.subheadline)
                .foregroundStyle(.tint)
            Text(spot.title)
                .font(.title2.bold())
            if spot.isFree == true {
                Text("무료")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(SpotFormatting.dateRange(start: spot.startsAt, end: spot.endsAt), systemImage: "calendar")
            if let place = spot.placeName {
                Label(place, systemImage: "mappin.and.ellipse")
            }
            if let address = spot.address {
                Label(address, systemImage: "map")
            }
            if let distance = SpotFormatting.distance(meters: spot.distanceMeters) {
                Label("내 위치에서 \(distance)", systemImage: "figure.walk")
            }
        }
        .font(.subheadline)
    }

    private var map: some View {
        SpotMapView(spots: [spot], center: spot.coordinate, zoom: 15, showsUserLocation: false)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        SpotDetailView(spot: SampleSpots.all[0])
    }
}
