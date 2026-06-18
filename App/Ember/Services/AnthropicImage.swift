import Foundation
import UIKit

/// A photo encoded for the Anthropic vision API: base64 payload plus its media type.
///
/// Produced by `encodeForVision(_:)` (Step 2) and consumed by `imageContentBlock(_:)`,
/// which emits the API's `image` content block. Kept as a small typed handle so the
/// Stage-3 capture/UI wiring has a stable value to pass into `AnthropicClient.sendVision`.
struct VisionImage {
    let base64: String
    /// The API-spelled media type, e.g. `"image/jpeg"`. This is the value for the
    /// snake_case `media_type` key in the image block's `source`.
    let mediaType: String
}

/// Builds the Anthropic Messages API image content block over the existing generic
/// `[String: Any]` block structure used by the rest of the client.
///
/// Emits exactly:
/// ```
/// ["type": "image",
///  "source": ["type": "base64", "media_type": <String>, "data": <base64 String>]]
/// ```
/// Note `media_type` is the API-spelled (snake_case) key — load-bearing wire format.
/// Pure and deterministic given its input; no networking, no UIKit.
func imageContentBlock(_ image: VisionImage) -> [String: Any] {
    [
        "type": "image",
        "source": [
            "type": "base64",
            "media_type": image.mediaType,
            "data": image.base64,
        ],
    ]
}

// MARK: - UIImage encoding

/// Anthropic's documented vision long-edge guidance: above ~1568 px the API downscales
/// server-side anyway, so encoding larger just wastes upload bytes.
private let maxLongEdge: CGFloat = 1568
/// Starting JPEG quality — small payloads for photos while staying visually faithful.
private let initialJpegQuality: CGFloat = 0.7
/// Floor for the quality step-down so we never produce unusably degraded data.
private let minJpegQuality: CGFloat = 0.3
/// Conservative budget under Anthropic's ~5 MB per-image limit ("no oversized payloads").
private let maxBytes = 4_500_000

/// Downscales `image` so its longest edge is ≤ `maxLongEdge`, JPEG-encodes it within the
/// `maxBytes` budget (stepping quality down from `initialJpegQuality` toward `minJpegQuality`
/// if needed), and returns the base64 payload with `media_type` `"image/jpeg"`.
///
/// JPEG is chosen as the smallest payload for photos and keeps the block builder to a single
/// known media type. Returns `nil` if JPEG encoding fails (caller surfaces this in Stage 3).
func encodeForVision(_ image: UIImage) -> VisionImage? {
    let original = image.size
    let longEdge = max(original.width, original.height)

    // Redraw at the bounded size (scale 1) only when the source exceeds the long-edge bound.
    let target: UIImage
    if longEdge > maxLongEdge, longEdge > 0 {
        let factor = maxLongEdge / longEdge
        let newSize = CGSize(width: original.width * factor, height: original.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        target = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    } else {
        target = image
    }

    guard var data = target.jpegData(compressionQuality: initialJpegQuality) else { return nil }

    var quality = initialJpegQuality
    while data.count > maxBytes, quality > minJpegQuality {
        quality = max(minJpegQuality, quality - 0.1)
        guard let stepped = target.jpegData(compressionQuality: quality) else { break }
        data = stepped
    }

    return VisionImage(base64: data.base64EncodedString(), mediaType: "image/jpeg")
}
