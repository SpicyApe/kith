// ImageResizer.swift — docs/07-games-hub.md §Product rules → "Profile (2026-09-13)".
//
// Turns a `PhotosPicker` selection into the JPEG `AppModel.uploadAvatar` sends: centre
// square, 256 px a side, quality 0.8, kept under 1 MB. UIKit only — no KithCore/model
// dependency, so it is easy to unit test in isolation if that is ever worth doing.

import UIKit

enum ImageResizer {
    /// Centre-crops `data`'s image to a square, resizes it to `side` points, and
    /// JPEG-encodes it at `quality`. Returns nil if `data` doesn't decode as an image.
    /// Drops quality once if the first encode is still over 1 MB (256 px JPEGs almost
    /// never are, but nothing here should ever hand the network more than that).
    static func squareJPEG(from data: Data, side: CGFloat = 256, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        let target = CGSize(width: side, height: side)
        // Render at 1x regardless of the device's screen scale — otherwise a 3x device
        // renders a 256 pt target at 768 px, three times the size (and roughly nine times
        // the bytes) this is meant to produce.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            // Scale so the shorter side exactly fills `side`, then centre the (now
            // larger) image in the square target — a draw-time centre-crop that also
            // respects `imageOrientation` for free, since `UIImage.draw` does.
            let shortSide = min(image.size.width, image.size.height)
            let scale = side / shortSide
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (side - scaledSize.width) / 2, y: (side - scaledSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        guard var jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        let oneMegabyte = 1_000_000
        if jpeg.count > oneMegabyte, let lower = resized.jpegData(compressionQuality: 0.5) {
            jpeg = lower
        }
        return jpeg
    }
}
