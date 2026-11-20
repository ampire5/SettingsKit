import AppKit

/// Searchable keyboard shortcuts and gestures for an overlay in a host window.
@MainActor public final class CheatSheetView: NSView, NSSearchFieldDelegate {
    private static let margin: CGFloat = 16
    private static let columnGap: CGFloat = 24
    private static let columnWidth: CGFloat = 320

    private static let primaryText = NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 247 / 255, alpha: 1)
    private static let secondaryText = NSColor(srgbRed: 154 / 255, green: 154 / 255, blue: 162 / 255, alpha: 1)

    private lazy var panel = NSVisualEffectView()
    private lazy var scrim = ScrimView()
    private lazy var title = NSTextField(labelWithString: "Keys and Gestures")
    private lazy var search = NSSearchField()
    private lazy var close = NSButton()
    private lazy var scroll = NSScrollView()
    private lazy var document = DocumentView()
    private lazy var empty = NSTextField(labelWithString: "No matching keys or gestures")
    private var content: [[SectionView]] = []
    private var sheet: Sheet?
    private var query = ""
    private var contentWidth: CGFloat = 0
    private weak var previousResponder: NSResponder?

    public var onClose: (() -> Void)?
    public var isOpen: Bool { !isHidden }

    private final class ScrimView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            // A dark veil over the HUD material keeps dense text legible on bright photos.
            NSColor(white: 0, alpha: 0.38).setFill()
            dirtyRect.fill()
        }
    }

    private final class DocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func buildInterface() {
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.cornerCurve = .continuous
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        addSubview(panel)
        panel.addSubview(scrim)

        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = CheatSheetView.primaryText
        search.placeholderString = "Search keys or actions"
        search.setAccessibilityLabel("Search keys or actions")
        search.sendsSearchStringImmediately = true
        search.delegate = self
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        close.imagePosition = .imageOnly
        close.bezelStyle = .accessoryBarAction
        close.setAccessibilityLabel("Close Keys and Gestures")
        close.toolTip = "Close (Esc)"
        close.target = self
        close.action = #selector(closeClicked)
        search.nextKeyView = close
        close.nextKeyView = search

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = document
        scroll.setAccessibilityLabel("Keys and gestures results")
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = CheatSheetView.secondaryText
        empty.isHidden = true
        document.addSubview(empty)
        for view in [title, search, close, scroll] { panel.addSubview(view) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public func show(_ updated: Sheet) {
        guard isHidden else { return }
        if sheet == nil { buildInterface() }
        let changed = updated != sheet || !query.isEmpty
        let responder = window?.firstResponder
        // AppKit reuses the field editor for the search field. Remember its owning control.
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            previousResponder = editor.delegate as? NSView
        } else {
            previousResponder = responder
        }
        sheet = updated
        search.stringValue = ""
        query = ""
        if changed { rebuildResults() }
        isHidden = false
        needsLayout = true
        focusSearch()
        scrollTo(y: 0)
    }

    public func focusSearch() {
        window?.makeFirstResponder(search)
    }

    public func update(_ updated: Sheet) {
        guard isOpen, sheet != updated else { return }
        sheet = updated
        rebuildResults()
        scrollTo(y: 0)
    }

    public func hide() {
        guard isOpen else { return }
        let responder = window?.firstResponder
        let ownsFocus = responder === close || responder === search || responder === scroll
            || (responder != nil && responder === search.currentEditor())
            || (responder as? NSView)?.isDescendant(of: panel) == true
        isHidden = true
        if ownsFocus, let window, !window.makeFirstResponder(previousResponder) {
            window.makeFirstResponder(nil)
        }
        previousResponder = nil
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard search.stringValue != query else { return }
        query = search.stringValue
        rebuildResults()
        scrollTo(y: 0)
    }

    @objc private func closeClicked() { onClose?() }

    public override func layout() {
        super.layout()
        guard isOpen else { return }
        let inset = Self.margin
        let maxWidth = 3 * Self.columnWidth + 2 * Self.columnGap + 2 * inset
        let width = max(1, min(bounds.width - 2 * inset, maxWidth))
        let height = max(1, min(bounds.height - 2 * inset, 710))
        panel.frame = NSRect(x: floor((bounds.width - width) / 2), y: floor((bounds.height - height) / 2),
                             width: width, height: height)
        scrim.frame = panel.bounds
        title.frame = NSRect(x: inset, y: height - 37, width: max(1, width - 2 * inset - 36), height: 22)
        close.frame = NSRect(x: width - inset - 28, y: height - 41, width: 28, height: 28)
        search.frame = NSRect(x: inset, y: height - 73, width: max(1, width - 2 * inset), height: 26)
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: max(1, height - 85))
        layoutResults(width: scroll.contentSize.width)
    }

    private func rebuildResults() {
        for section in content.joined() { section.removeFromSuperview() }
        content = (sheet?.filtered(by: query) ?? []).map { group in
            group.map { section in
                let view = SectionView(section)
                document.addSubview(view)
                return view
            }
        }
        empty.isHidden = !content.isEmpty
        contentWidth = 0
        needsLayout = true
    }

    private func layoutResults(width: CGFloat) {
        let inset = Self.margin
        let available = max(1, width - 2 * inset)
        if contentWidth != width {
            contentWidth = width
            let sections = content.flatMap { $0 }
            let columns: [[SectionView]]
            if available >= 3 * Self.columnWidth + 2 * Self.columnGap {
                columns = content
            } else if available >= 2 * Self.columnWidth + Self.columnGap, sections.count > 1 {
                let half = sections.reduce(0) { $0 + $1.rowCount + 2 } / 2
                var firstHeight = 0
                let cut = sections.dropLast().prefix { section in
                    guard firstHeight < half else { return false }
                    firstHeight += section.rowCount + 2
                    return true
                }.count
                columns = [Array(sections.prefix(cut)), Array(sections.dropFirst(cut))]
            } else {
                columns = [sections]
            }

            let count = max(1, columns.count)
            let columnWidth = floor((available - CGFloat(count - 1) * Self.columnGap) / CGFloat(count))
            var height: CGFloat = 36
            for (index, column) in columns.enumerated() {
                let x = inset + CGFloat(index) * (columnWidth + Self.columnGap)
                var y: CGFloat = 4
                for section in column {
                    let size = section.measure(width: columnWidth)
                    section.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
                    y += size.height + 20
                }
                height = max(height, y)
            }
            empty.frame = NSRect(x: inset, y: 4, width: available, height: 24)
            document.frame.size = NSSize(width: width, height: height)
        }
        // Keep the scroll position in range when a resize reveals more rows.
        scrollTo(y: scroll.contentView.bounds.minY)
    }

    private func scrollTo(y: CGFloat) {
        let clip = scroll.contentView
        let end = max(0, document.bounds.height - clip.bounds.height)
        let target = min(max(0, y), end)
        guard target != clip.bounds.minY else { return }
        clip.scroll(to: NSPoint(x: 0, y: target))
        scroll.reflectScrolledClipView(clip)
    }

    public func scrollPage(down: Bool) {
        let viewport = scroll.contentView.bounds
        let distance = max(1, viewport.height - 20)
        scrollTo(y: viewport.minY + (down ? distance : -distance))
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard isOpen, frame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { onClose?() }
    }
    public override func rightMouseDown(with event: NSEvent) {}
    public override func otherMouseDown(with event: NSEvent) {}
    public override func scrollWheel(with event: NSEvent) {}
    public override func magnify(with event: NSEvent) {}
    public override func rotate(with event: NSEvent) {}
    public override func swipe(with event: NSEvent) {}
    public override func smartMagnify(with event: NSEvent) {}
    public override func pressureChange(with event: NSEvent) {}

    /// The arrow over the sheet, not the viewer's hand.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    public override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }

    // MARK: Content

    /// Host-supplied sections in reading order, grouped into up to three preferred columns.
    public struct Sheet: Equatable {
        public struct Section: Equatable {
            public let title: String
            public let rows: [(keys: String, title: String)]

            public init(title: String, rows: [(keys: String, title: String)]) {
                self.title = title
                self.rows = rows
            }

            public static func == (a: Section, b: Section) -> Bool {
                a.title == b.title && a.rows.elementsEqual(b.rows) { $0.keys == $1.keys && $0.title == $1.title }
            }
        }

        public let columns: [[Section]]

        public init(columns: [[Section]]) {
            precondition(columns.count <= 3, "A shortcut sheet supports at most three columns")
            self.columns = columns
        }

        func filtered(by query: String) -> [[Section]] {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let groups = columns.map { column in
                column.compactMap { section -> Section? in
                    let rows = query.isEmpty || section.title.localizedStandardContains(query) ? section.rows
                        : section.rows.filter { $0.keys.localizedStandardContains(query) || $0.title.localizedStandardContains(query) }
                    return rows.isEmpty ? nil : Section(title: section.title, rows: rows)
                }
            }
            return groups.filter { !$0.isEmpty }
        }
    }

    /// One native text element per section keeps layout bounded, with each input beside its action in reading order.
    private final class SectionView: NSView {
        private let heading: NSTextField
        private let body = NSTextField(wrappingLabelWithString: "")
        let rowCount: Int

        init(_ section: Sheet.Section) {
            heading = NSTextField(labelWithString: section.title)
            rowCount = section.rows.count
            super.init(frame: .zero)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            heading.textColor = CheatSheetView.primaryText
            let row = NSMutableParagraphStyle()
            row.paragraphSpacing = 5
            row.lineBreakMode = .byWordWrapping
            let keys: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: CheatSheetView.primaryText, .paragraphStyle: row,
            ]
            let actions: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: CheatSheetView.secondaryText, .paragraphStyle: row,
            ]
            let text = NSMutableAttributedString()
            for (index, binding) in section.rows.enumerated() {
                if index > 0 { text.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: row])) }
                text.append(NSAttributedString(string: binding.keys, attributes: keys))
                let separator = binding.keys.isEmpty ? "" : "   "
                text.append(NSAttributedString(string: separator + binding.title, attributes: actions))
            }
            body.attributedStringValue = text
            addSubview(heading)
            addSubview(body)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        func measure(width: CGFloat) -> NSSize {
            heading.frame = NSRect(x: 0, y: 0, width: width, height: 18)
            let rect = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            let bodyHeight = ceil(body.cell?.cellSize(forBounds: rect).height ?? 0)
            body.frame = NSRect(x: 0, y: 24, width: width, height: bodyHeight)
            return NSSize(width: width, height: body.frame.maxY)
        }

        override var isFlipped: Bool { true }
    }

}
