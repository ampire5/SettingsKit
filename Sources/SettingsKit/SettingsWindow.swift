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
        let window = NSWindow(contentRect: host.view.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.contentViewController = host
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Never full screen (⌃⌘F acts on the key window): a settings window stays a window.
        window.collectionBehavior.insert(.fullScreenNone)
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
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.layoutIfNeeded()
        if !pinSidebarWidth() { DispatchQueue.main.async { [weak self] in _ = self?.pinSidebarWidth() } }
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

    init(pages: [SettingsPage], page: String?) {
        self.pages = pages
        index = SettingsSearch(pages: pages)
        self.page = pages.first { $0.id == page }?.id ?? pages.first?.id ?? ""
        currentSection = currentPage?.sections.first?.title ?? ""
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

    func isMatch(_ rowID: String) -> Bool { matches[page]?.contains(rowID) ?? false }

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
            if let page = ui.currentPage {
                PageView(page: page).id(page.id)
            }
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
