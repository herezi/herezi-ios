import Domain
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

/// 히어로 카드(DESIGN §6.13): 사진을 불러온 상태에서도 카드 크기가 7:4로 고정되고
/// 아래쪽에 그라데이션·흰 제목이 보여야 한다(#23). 스냅샷 대신 렌더링한 픽셀 몇 개만 본다.
@MainActor
struct HeroCardLayoutTests {
    private let width: CGFloat = 350

    private var spot: Spot {
        Spot(
            id: "hero", title: "서울빛초롱축제", category: .festival,
            coordinate: Coordinate(latitude: 37.5663, longitude: 126.9779), placeName: "청계천",
            startsAt: Date(), isFree: true, imageURL: URL(string: "https://example.com/hero.jpg"),
            source: "seoul_culture", fetchedAt: Date(), distanceMeters: 350)
    }

    /// 아주 길쭉한 흰 사진. scaledToFill로 카드보다 훨씬 커지는 경우.
    private func tallWhitePhoto() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 1_000), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 1_000))
        }
    }

    private func render() throws -> CGImage {
        let card = HeroCard(
            spot: spot, badge: nil, meta: "축제·행사 · 350m · 무료", isSaved: false, onToggleSave: {},
            media: AnyView(Image(uiImage: tallWhitePhoto()).resizable().scaledToFill())
        )
        .frame(width: width)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    /// (x, y) 픽셀 밝기 0...255.
    private func brightness(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
    }

    @Test func 사진이_커도_카드는_7대4를_지킨다() throws {
        let image = try render()
        #expect(image.width == Int(width))
        #expect(image.height == Int(width * 4 / 7))
    }

    @Test func 사진_위_아래쪽에_그라데이션이_깔린다() throws {
        let image = try render()
        // 위쪽 30%까지는 그라데이션 0% → 흰 사진 그대로.
        #expect(brightness(image, image.width / 2, image.height / 10) > 240)
        // 맨 아래 오른쪽(글자 없는 곳)은 잉크 85% → 어둡다.
        #expect(brightness(image, image.width - 4, image.height - 3) < 90)
    }

    @Test func 사진_위에_흰_제목이_보인다() throws {
        let image = try render()
        // 제목 줄이 놓이는 아래 왼쪽 영역에 흰 글자 픽셀이 있어야 한다(배경은 60~85% 잉크로 어둡다).
        let rows = (image.height * 6 / 10)..<(image.height - 16)
        let columns = 16..<(image.width / 2)
        let hasWhiteText = rows.contains { y in
            columns.contains { x in brightness(image, x, y) > 220 }
        }
        #expect(hasWhiteText)
    }
}
