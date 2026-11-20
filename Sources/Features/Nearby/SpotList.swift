import Domain
import SwiftUI

struct SpotList: View {
    let spots: [Spot]
    let refresh: @MainActor () async -> Void

    var body: some View {
        List(spots) { spot in
            NavigationLink(value: spot) {
                SpotRow(spot: spot)
            }
        }
        .listStyle(.plain)
        .refreshable { await refresh() }
    }
}

struct SpotRow: View {
    let spot: Spot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(spot.category.displayName, systemImage: spot.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(.tint)
                if spot.isFree == true {
                    Text("무료")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }
                Spacer()
                if let distance = SpotFormatting.distance(meters: spot.distanceMeters) {
                    Text(distance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(spot.title)
                .font(.headline)
            Text(SpotFormatting.dateRange(start: spot.startsAt, end: spot.endsAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
