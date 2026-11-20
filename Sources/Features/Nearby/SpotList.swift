import DesignSystem
import Domain
import SwiftUI

struct SpotList: View {
    let spots: [Spot]
    let refresh: @MainActor () async -> Void

    var body: some View {
        List(spots) { spot in
            SpotRowLink(spot: spot) {
                SpotCard(spot: spot)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.hz.bgPrimary)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }
}
