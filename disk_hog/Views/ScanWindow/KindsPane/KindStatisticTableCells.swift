import AppKit

final class KindColorCellView: NSTableCellView {
    private let swatchView: NSImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(color: NSColor) {
        swatchView.image = Self.swatchImage(color: color)
    }

    private func setup() {
        imageView = swatchView
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchView.imageScaling = .scaleAxesIndependently
        addSubview(swatchView)
        NSLayoutConstraint.activate([
            swatchView.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatchView.trailingAnchor.constraint(equalTo: trailingAnchor),
            swatchView.topAnchor.constraint(equalTo: topAnchor),
            swatchView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private static func swatchImage(color: NSColor) -> NSImage {
        let cacheKey: KindColorSwatchCacheKey = KindColorSwatchCacheKey(color: color)
        if let cachedImage: NSImage = swatchImageCache[cacheKey] {
            return cachedImage
        }

        let imageSize: NSSize = NSSize(
            width: ScanWindowMetrics.kindColorColumnWidth,
            height: ScanWindowMetrics.tableRowHeight
        )
        let bitmap: NSBitmapImageRep = NSBitmapImageRep(
            treemapRGBBitmapWithWidth: Int(imageSize.width),
            height: Int(imageSize.height)
        )
        let renderer: TreemapCushionRenderer = TreemapCushionRenderer(
            rect: NSRect(origin: .zero, size: imageSize)
        )
        renderer.setColor(color)
        renderer.addRidgeByHeightFactor(ScanWindowMetrics.kindSwatchCushionRidgeHeightFactor)
        renderer.renderCushion(in: bitmap)
        bitmap.size = imageSize
        let image: NSImage = bitmap.treemapSuitableImage()
        swatchImageCache[cacheKey] = image
        return image
    }

    private static var swatchImageCache: [KindColorSwatchCacheKey: NSImage] = [:]
}

private struct KindColorSwatchCacheKey: Hashable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
    let width: Int
    let height: Int

    init(color: NSColor) {
        let rgbColor: NSColor = color.usingColorSpace(.genericRGB) ?? color
        self.red = Self.quantizedComponent(rgbColor.redComponent)
        self.green = Self.quantizedComponent(rgbColor.greenComponent)
        self.blue = Self.quantizedComponent(rgbColor.blueComponent)
        self.alpha = Self.quantizedComponent(rgbColor.alphaComponent)
        self.width = Int(ScanWindowMetrics.kindColorColumnWidth)
        self.height = Int(ScanWindowMetrics.tableRowHeight)
    }

    private static func quantizedComponent(_ component: CGFloat) -> Int {
        Int((component * 255).rounded())
    }
}

final class KindTextCellView: NSTableCellView {
    private let text: NSTextField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(string: String, alignment: NSTextAlignment) {
        text.stringValue = string
        text.alignment = alignment
    }

    private func setup() {
        textField = text
        text.font = NSFont.systemFont(ofSize: ScanWindowMetrics.tableFontSize)
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScanWindowMetrics.tableCellHorizontalPadding),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScanWindowMetrics.tableCellHorizontalPadding),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}


enum KindColumnID {
    static let color: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("color")
    static let kind: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kind")
    static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("size")
    static let files: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("files")
}


enum KindCellID {
    static let color: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindColorCell")
    static let kind: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindTextCell")
    static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindSizeCell")
    static let files: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("kindFilesCell")
}


enum KindSortKey {
    static let kindName: String = "kindName"
    static let size: String = "size"
    static let fileCount: String = "fileCount"
}
