import SafariServices
import SwiftUI

/// 인앱 브라우저 (SFSafariViewController). 원문 보기, 정보 출처 링크에 쓴다.
public struct SafariView: UIViewControllerRepresentable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color.hz.ink)
        return controller
    }

    public func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// `.sheet(item:)`용 URL 래퍼.
public struct BrowserLink: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: URL { url }

    public init(_ url: URL) {
        self.url = url
    }
}
