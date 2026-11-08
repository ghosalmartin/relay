import Presentation
import SwiftUI

struct ConnectionBannerView: View {
    let banner: ConnectionBanner

    var body: some View {
        Label(banner.message, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .accessibilityIdentifier("inbox.banner")
    }

    private var symbol: String {
        switch banner {
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .phoneUnreachable: "iphone.slash"
        }
    }
}
