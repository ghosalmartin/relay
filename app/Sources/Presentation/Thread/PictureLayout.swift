import Foundation

/// How big a picture is drawn in a bubble.
public enum PictureLayout {
    public static let maxWidth: CGFloat = 280
    public static let maxHeight: CGFloat = 320

    /// The exact size, so the bubble hugs the picture instead of leaving space around it.
    public static func size(fitting picture: CGSize) -> CGSize {
        guard picture.width > 0, picture.height > 0 else { return CGSize(width: maxWidth, height: maxWidth) }
        let scale = min(maxWidth / picture.width, maxHeight / picture.height)
        return CGSize(width: picture.width * scale, height: picture.height * scale)
    }
}
