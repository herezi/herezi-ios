import DesignSystem
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("출처: \(spot.source)")
                    Text("갱신 \(SpotFormatting.relativeTime(spot.fetchedAt, now: Date()))")
                }
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
            HStack(spacing: 6) {
                if spot.isEnded { HZBadge(.ended) }
                if spot.isFree == true { HZBadge(.free) }
            }
        }
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                SpotFormatting.cardPeriod(start: spot.startsAt, end: spot.endsAt, now: Date()).text,
                systemImage: "calendar")
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

#Preview("종료됨") {
    NavigationStack {
        SpotDetailView(spot: SampleSpots.all.first { $0.id == SampleSpots.endedID } ?? SampleSpots.all[0])
    }
}
