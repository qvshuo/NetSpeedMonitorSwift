import AppKit

final class MenuBarIconGenerator {
    private static let iconSize = NSSize(width: 82, height: 24)
    
    static func generateIcon(
        text: String,
        font: NSFont = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
    ) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { rect in
            let style = NSMutableParagraphStyle()
            style.alignment = .right

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: style
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)

            return true
        }

        image.isTemplate = true
        return image
    }
}
