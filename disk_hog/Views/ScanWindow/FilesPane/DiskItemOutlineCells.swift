import AppKit

final class DiskItemNameCellView: NSTableCellView {
    private let iconImageView: NSImageView = NSImageView()
    private let titleTextField: NSTextField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(item: DiskItem) {
        iconImageView.image = NSWorkspace.shared.icon(forFile: item.path)
        titleTextField.stringValue = item.displayName
    }

    private func setup() {
        imageView = iconImageView
        textField = titleTextField
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.lineBreakMode = .byClipping
        titleTextField.font = NSFont.systemFont(ofSize: ScanWindowMetrics.tableFontSize)
        addSubview(iconImageView)
        addSubview(titleTextField)
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScanWindowMetrics.outlineCellHorizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: ScanWindowMetrics.outlineIconWidth),
            iconImageView.heightAnchor.constraint(equalToConstant: ScanWindowMetrics.outlineIconWidth),
            titleTextField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: ScanWindowMetrics.outlineIconTextSpacing),
            titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScanWindowMetrics.outlineCellHorizontalPadding),
            titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}


final class DiskItemSizeCellView: NSTableCellView {
    private let sizeTextField: NSTextField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(item: DiskItem, usePhysicalSize: Bool) {
        sizeTextField.stringValue = ByteCountFormatter.string(fromByteCount: Int64(item.sizeValue(usePhysicalSize: usePhysicalSize)), countStyle: .file)
    }

    private func setup() {
        textField = sizeTextField
        sizeTextField.alignment = .right
        sizeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: ScanWindowMetrics.tableFontSize, weight: .regular)
        sizeTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sizeTextField)
        NSLayoutConstraint.activate([
            sizeTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScanWindowMetrics.outlineCellHorizontalPadding),
            sizeTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScanWindowMetrics.outlineCellHorizontalPadding),
            sizeTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}


enum DiskItemOutlineColumnID {
    static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("name")
    static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("size")
}


enum DiskItemOutlineCellID {
    static let name: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("nameCell")
    static let size: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("sizeCell")
}
