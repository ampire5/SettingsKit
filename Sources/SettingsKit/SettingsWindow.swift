import AppKit
import SwiftUI

/// The settings window: sidebar (search, pages, sub-sections of the current page) and the page on the right.
/// One per app; the app keeps it and calls `show(page:)`.
@MainActor
public final class SettingsWindowController: NSWindowController {
    private let ui: SettingsUIState
    /// The window's look (`.glass` unless the app asks for `.plain`).
    public let style: SettingsStyle
    private nonisolated(unsafe) var closeObserver: NSObjectProtocol?
    /// Sidebar width (IINA: 200 pt): the column in plain; in glass the visible panel, so the column adds the
    /// panel's inset on both sides and page titles get the same room in both styles.
    static func sidebarWidth(_ style: SettingsStyle) -> CGFloat {
        switch style {
        case .plain: 200
        case .glass: 200 + 2 * GlassMetrics.sidebarInset
        }
    }

    /// - Parameters:
    ///   - autosaveName: frame autosave name of the window.
    ///   - lastPageDefaultsKey: `UserDefaults` key that remembers the open page.
    ///   - style: a floating glass sidebar and glass cards, or the plain look.
    public init(pages: [SettingsPage], model: SettingsModel, autosaveName: String, lastPageDefaultsKey: String,
                style: SettingsStyle = .glass) {
        self.style = style
        model.register(pages)
        let lastPage = UserDefaults.standard.string(forKey: lastPageDefaultsKey)
        ui = SettingsUIState(pages: pages, page: lastPage)
        let host = NSHostingController(rootView: SettingsRootView(ui: ui, model: model)
            .environment(\.settingsStyle, style))
        host.sceneBridgingOptions = [.toolbars]
        host.view.frame = NSRect(x: 0, y: 0, width: 782, height: 637)  // IINA's default size
        let window = SettingsWindow(contentRect: host.view.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.contentViewController = host
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = true
        // Auxiliary: shown over a full-screen window, in its space. The window itself never goes full screen
        // (`toggleFullScreen` is a no-op, so ⌃⌘F and the menu item do nothing); AppKit allows only one of
        // primary/auxiliary/none, so `.fullScreenNone` cannot be kept alongside.
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        // The green button would call `toggleFullScreen`; it zooms instead, as with `.fullScreenNone`.
        if let zoom = window.standardWindowButton(.zoomButton) {
            zoom.target = window
            zoom.action = #selector(NSWindow.performZoom(_:))
        }
        window.contentMinSize = NSSize(width: 640, height: 400)
        if !window.setFrameUsingName(autosaveName) { window.center() }
        window.setFrameAutosaveName(autosaveName)
        super.init(window: window)
        let ui = ui
        ui.onPageChange = { [weak window] id in
            UserDefaults.standard.set(id, forKey: lastPageDefaultsKey)
            window?.title = ui.currentPage?.title ?? ""
        }
        window.title = ui.currentPage?.title ?? ""
        // A value typed and then left by a page switch or ⌘W is written, as on focus loss.
        ui.willChangePage = { [weak self] in self?.endEditing() }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endEditing() }
        }
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Brings the window to the front, on `page` when given (otherwise the page it was on).
    public func show(page: String?) {
        if let page, ui.pages.contains(where: { $0.id == page }) { ui.select(page) }
        moveToWorkingScreen()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.layoutIfNeeded()
        if !pinSidebarWidth() { DispatchQueue.main.async { [weak self] in _ = self?.pinSidebarWidth() } }
    }

    /// Puts the window on the screen the user is working on: the key window's, else the main window's (never this
    /// one), else the pointer's, else the main screen's. The autosaved frame stays when it is already there.
    /// A window the user is working in (key) is left where it is.
    private func moveToWorkingScreen() {
        guard let window, !window.isKeyWindow else { return }
        func screen(of other: NSWindow?) -> NSScreen? { other === window ? nil : other?.screen }
        let pointer = NSEvent.mouseLocation
        let target = screen(of: NSApp.keyWindow) ?? screen(of: NSApp.mainWindow)
            ?? NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let target else { return }
        let frame = SettingsWindowPlacement.frame(saved: window.frame, in: target.visibleFrame)
        if frame != window.frame { window.setFrame(frame, display: false) }
    }

    /// `navigationSplitViewColumnWidth` is not applied when the split view is hosted in an AppKit window
    /// (the sidebar item keeps SwiftUI's default minimum of 140 pt and opens at 144); fix the item's width.
    @discardableResult
    private func pinSidebarWidth() -> Bool {
        func split(in view: NSView) -> NSSplitView? {
            (view as? NSSplitView) ?? view.subviews.lazy.compactMap(split).first
        }
        guard let view = window?.contentView, let splitView = split(in: view),
              let controller = splitView.delegate as? NSSplitViewController,
              let sidebar = controller.splitViewItems.first(where: { $0.behavior == .sidebar })
        else { return false }
        sidebar.canCollapse = false
        let width = Self.sidebarWidth(style)
        sidebar.minimumThickness = width
        sidebar.maximumThickness = width
        splitView.setPosition(width, ofDividerAt: 0)
        return true
    }

    /// Ends the edit of a settings field, which writes its text as focus loss does (the search field and a
    /// focused sidebar are left alone). The window calls it before a page switch and on close; an app calls it
    /// before it quits.
    public func endEditing() {
        guard let window, let editor = window.firstResponder as? NSText, editor.isFieldEditor,
              !(editor.delegate is NSSearchField) else { return }
        window.makeFirstResponder(nil)
    }

    /// Puts `query` into the search field (the sidebar then lists only pages with matching rows).
    public func search(_ query: String) {
        ui.query = query
    }

    /// Opens a chevron row (`.group` or `.flags`) by its row id.
    public func expand(_ rowID: String) {
        ui.expanded.insert(rowID)
    }
}

/// The window's view state: open page, search, sub-section indicator, expanded rows.
@MainActor @Observable
final class SettingsUIState {
    let pages: [SettingsPage]
    @ObservationIgnored let index: SettingsSearch
    @ObservationIgnored var onPageChange: (String) -> Void = { _ in }
    /// Called before the page changes, while the old page's fields are still in the window.
    @ObservationIgnored var willChangePage: () -> Void = {}

    private(set) var page: String
    var query = "" {
        didSet { if query != oldValue { updateMatches() } }
    }
    /// The sub-section the indicator's dot is on.
    var currentSection = ""
    var expanded: Set<String> = []
    /// A sub-section clicked in the sidebar; the page scrolls to it and clears the request.
    var scrollRequest: String?
    /// page id → ids of the rows that match the query.
    private(set) var matches: [String: Set<String>] = [:]
    /// The pages opened so far, in the order they were first opened: their views stay in the window (hidden while
    /// another page is open), so going back to one is instant and keeps its scroll position. Building a page's
    /// controls again on every switch took 0.2–1.4 s of the main thread (LoupeBench settings, Intel iMac).
    private(set) var keptPages: [String] = []

    init(pages: [SettingsPage], page: String?) {
        self.pages = pages
        index = SettingsSearch(pages: pages)
        self.page = pages.first { $0.id == page }?.id ?? pages.first?.id ?? ""
        currentSection = currentPage?.sections.first?.title ?? ""
        keptPages = [self.page]
    }

    var currentPage: SettingsPage? { pages.first { $0.id == page } }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// All pages, or while searching only those with matching rows.
    var visiblePages: [SettingsPage] {
        isSearching ? pages.filter { matches[$0.id] != nil } : pages
    }

    func select(_ id: String) {
        guard id != page else { return }
        willChangePage()
        page = id
        if !keptPages.contains(id) { keptPages.append(id) }
        currentSection = currentPage?.sections.first?.title ?? ""
        scrollRequest = nil
        onPageChange(id)
    }

    /// ↑/↓ in the sidebar.
    func selectAdjacent(_ offset: Int) {
        let visible = visiblePages
        guard let i = visible.firstIndex(where: { $0.id == page }) else {
            if let first = visible.first { select(first.id) }
            return
        }
        let j = i + offset
        if visible.indices.contains(j) { select(visible[j].id) }
    }

    /// Whether the row matches the query. Rows pass their own page (`settingsPageID`), not the open one: a row that
    /// read `page` would update on every page switch, on every kept page.
    func isMatch(_ rowID: String, on pageID: String) -> Bool { matches[pageID]?.contains(rowID) ?? false }

    /// Whether the query appears in `text` (for flag items, which are not rows).
    func queryMatches(_ text: String) -> Bool {
        isSearching && text.localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func updateMatches() {
        var found: [String: Set<String>] = [:]
        for match in index.matches(query) { found[match.page, default: []].insert(match.rowID) }
        matches = found
        // Stay on a page with matches.
        if isSearching, found[page] == nil, let first = visiblePages.first { select(first.id) }
    }
}

struct SettingsRootView: View {
    let ui: SettingsUIState
    let model: SettingsModel
    @Environment(\.settingsStyle) private var style
    /// The window's width, for the glass style's background, which spans both columns.
    @State private var width: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(SettingsWindowController.sidebarWidth(style))
                .toolbar(removing: .sidebarToggle)
        } detail: {
            // Every kept page is in the stack; only the open one shows, takes clicks and is read by VoiceOver. ⇥ skips
            // the others' controls (`SettingsWindow.selectKeyView`): disabling them instead cost 150–300 ms per switch.
            ZStack {
                ForEach(ui.keptPages, id: \.self) { id in
                    if let page = ui.pages.first(where: { $0.id == id }) {
                        let open = id == ui.page
                        PageView(page: page, isOpen: open)
                            .opacity(open ? 1 : 0)
                            .allowsHitTesting(open)
                            .accessibilityHidden(!open)
                            .zIndex(open ? 1 : 0)
                    }
                }
            }
            .navigationTitle(ui.currentPage?.title ?? "")
        }
        .toolbar(removing: .sidebarToggle)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.settingsWindowWidth, width)
        .toolbar {
            // An invisible item keeps the unified toolbar at its full 52 pt height, as in IINA.
            ToolbarItem(placement: .primaryAction) { Color.clear.frame(width: 1, height: 1) }
                .sharedBackgroundVisibility(.hidden)
        }
        .environment(ui)
        .environment(model)
        .alert("Couldn't save the setting", isPresented: Binding(
            get: { model.writeFailure != nil },
            set: { if !$0 { model.clearWriteFailure() } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.writeFailure?.message ?? "")
        }
    }
}

/// Where the settings window goes on a screen (pure, so it can be tested without screens).
enum SettingsWindowPlacement {
    /// `saved` when its centre is already on the screen (`visible` is the screen's `visibleFrame`); otherwise
    /// the saved size, clamped to `visible`, centred in it.
    static func frame(saved: NSRect, in visible: NSRect) -> NSRect {
        if visible.contains(NSPoint(x: saved.midX, y: saved.midY)) { return saved }
        let size = NSSize(width: min(saved.width, visible.width), height: min(saved.height, visible.height))
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// The settings window: a plain window that never goes full screen, whose ⇥ and ⇧⇥ skip the controls of the kept
/// pages that are not open (drawn at opacity 0, still in the view tree).
final class SettingsWindow: NSWindow {
    override func toggleFullScreen(_ sender: Any?) {}

    override func selectKeyView(following view: NSView) {
        super.selectKeyView(following: view)
        skipInvisible { super.selectKeyView(following: $0) }
    }

    override func selectKeyView(preceding view: NSView) {
        super.selectKeyView(preceding: view)
        skipInvisible { super.selectKeyView(preceding: $0) }
    }

    /// Steps on while the focused control is invisible, at most once around the loop.
    private func skipInvisible(_ step: (NSView) -> Void) {
        var seen = Set<ObjectIdentifier>()
        while let view = focusedView, Self.isInvisible(view), seen.insert(ObjectIdentifier(view)).inserted {
            step(view)
        }
    }

    /// The focused control: a text field while its field editor has focus.
    private var focusedView: NSView? {
        if let editor = firstResponder as? NSText, editor.isFieldEditor { return editor.delegate as? NSView }
        return firstResponder as? NSView
    }

    static func isInvisible(_ view: NSView) -> Bool {
        var ancestor: NSView? = view
        while let a = ancestor {
            if a.isHidden || a.alphaValue == 0 || a.layer.map({ $0.opacity == 0 }) == true { return true }
            ancestor = a.superview
        }
        return false
    }
}
