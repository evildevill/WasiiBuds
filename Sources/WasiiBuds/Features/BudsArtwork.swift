import SwiftUI
import UIKit

private enum BudsImage {
    static let product: UIImage? = {
        guard let url = Bundle.module.url(forResource: "NordBuds3Pro", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()
}

struct BudsArtwork: View {
    var body: some View {
        if let product = BudsImage.product {
            Image(uiImage: product)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("OnePlus Nord Buds 3 Pro earbuds")
        } else {
            Image(systemName: "earbuds")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Studio.primary)
                .padding(80)
                .accessibilityLabel("Earbuds")
        }
    }
}

/// Frames one side of the bundled product render without duplicating the asset.
struct SingleBudArtwork: View {
    let side: UInt8

    var body: some View {
        GeometryReader { geometry in
            if let product = BudsImage.product {
                let scale = geometry.size.height / 500
                let budCenterX: CGFloat = side == 1 ? 290 : 670
                Image(uiImage: product)
                    .resizable()
                    .frame(width: 960 * scale, height: 960 * scale)
                    .position(x: geometry.size.width / 2 + (480 - budCenterX) * scale,
                              y: geometry.size.height / 2 - 12 * scale)
            } else {
                Image(systemName: side == 1 ? "earbud.left" : "earbud.right")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Studio.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
