import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

let source = URL(fileURLWithPath: "docs/media/neloa-introduction.mp4")
let output = URL(fileURLWithPath: ".build/product-video-frames", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let asset = AVURLAsset(url: source)
let duration = try await asset.load(.duration).seconds
let tracks = try await asset.loadTracks(withMediaType: .video)
guard let track = tracks.first else {
    throw NSError(domain: "NeloaVideoFrames", code: 3, userInfo: [NSLocalizedDescriptionKey: "The product film has no video track."])
}
let naturalSize = try await track.load(.naturalSize)
let transform = try await track.load(.preferredTransform)
let displaySize = naturalSize.applying(transform)
let width = Int(abs(displaySize.width.rounded()))
let height = Int(abs(displaySize.height.rounded()))
guard abs(duration - 27) < 0.1, width == 1_280, height == 720 else {
    throw NSError(
        domain: "NeloaVideoFrames",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Expected a 27-second 1280 × 720 film; found \(duration)s at \(width) × \(height)."]
    )
}
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

for second in [1.5, 6.5, 11.0, 15.5, 20.0, 24.5] {
    let image = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image
    let destinationURL = output.appendingPathComponent(String(format: "scene-%04.1f.png", second))
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw NSError(domain: "NeloaVideoFrames", code: 1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "NeloaVideoFrames", code: 2)
    }
}

print("Verified \(String(format: "%.2f", duration))s at \(width) × \(height); extracted frames to \(output.path)")
