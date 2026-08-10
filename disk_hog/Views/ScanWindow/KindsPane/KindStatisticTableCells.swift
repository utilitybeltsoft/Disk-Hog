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
        if let cachedImage: NSImage = swatchImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let imageSize: NSSize = NSSize(
            width: ScanWindowMetrics.kindColorColumnWidth,
            height: ScanWindowMetrics.tableRowHeight
        )
        guard let bitmap: NSBitmapImageRep = NSBitmapImageRep.treemapImageRepCompatible(
            withBounds: NSRect(origin: .zero, size: imageSize),
            backingScaleFactor: 1,
            colorSpace: .genericRGB
        ) else {
            let image: NSImage = NSImage(size: imageSize)
            image.lockFocus()
            color.drawSwatch(in: NSRect(origin: .zero, size: imageSize))
            image.unlockFocus()
            return image
        }
        let renderer: TreemapCushionRenderer = TreemapCushionRenderer(
            rect: NSRect(origin: .zero, size: imageSize)
        )
        renderer.setColor(color)
        renderer.addRidgeByHeightFactor(ScanWindowMetrics.kindSwatchCushionRidgeHeightFactor)
        renderer.renderCushion(in: bitmap)
        let image: NSImage = bitmap.treemapSuitableImage()
        swatchImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static let swatchImageCache: NSCache<KindColorSwatchCacheKey, NSImage> = {
        let cache: NSCache<KindColorSwatchCacheKey, NSImage> = NSCache()
        cache.countLimit = 64
        return cache
    }()
}

private final class KindColorSwatchCacheKey: NSObject {
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

    override var hash: Int {
        var hasher: Hasher = Hasher()
        hasher.combine(red)
        hasher.combine(green)
        hasher.combine(blue)
        hasher.combine(alpha)
        hasher.combine(width)
        hasher.combine(height)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let otherKey: KindColorSwatchCacheKey = object as? KindColorSwatchCacheKey else {
            return false
        }
        return red == otherKey.red
            && green == otherKey.green
            && blue == otherKey.blue
            && alpha == otherKey.alpha
            && width == otherKey.width
            && height == otherKey.height
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
