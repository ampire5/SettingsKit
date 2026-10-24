import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One picture an icon setting can take: the value written (`word`), where its picture is and the heading it goes
/// under in the grid.
public struct IconChoice {
    /// The value written to the store.
    public var word: String
    /// The picture's file (.png, .icns or any format ImageIO reads). Its thumbnails are made from the file at the size
    /// shown, off the main thread; the picture itself is never decoded whole.
    public var file: URL?
    /// A picture in memory, for a choice without a file (drawn as it is: keep it small).
    public var image: NSImage?
    /// The heading the choice goes under in the grid ("Built-in", "Yours"); headings show when there is more than one.
    public var section: String

    public init(word: String, file: URL? = nil, image: NSImage? = nil, section: String = "") {
        self.word = word
        self.file = file
        self.image = image
        self.section = section
    }

    /// The name shown: a file path by its file name, so a long path stays readable.
    public var title: String { IconChoice.title(of: word) }

    static func title(of word: String) -> String {
        word.contains("/") ? (word as NSString).lastPathComponent : word
    }
}

/// Thumbnails of picture files, made at the size they are shown with ImageIO's thumbnail (never the full picture: an
/// 85-item menu of 1 MB PNGs drawn at 32 pt took ~1 s of the main thread to show, LoupeBench settings, Intel iMac),
/// off the main thread, a few at a time, the newest ask first (what was just scrolled to). Kept by file, date, size and
/// pixel size, within `byteLimit`.
actor IconThumbnails {
    static let shared = IconThumbnails()

    /// Decodes at once: half the physical cores, at most 4. 85 PNGs of ~1024², 0.6–1 MB, at 168 px on an Intel
    /// i7-10700K (8 cores), all of them / the median one: 1 at a time 650 / 7.7 ms, 2: 337 / 7.9, 4: 196 / 9.1,
    /// 8: 140 / 12.8 — past 4 the whole machine goes for little.
    static let width = max(1, min(4, physicalCores() / 2))
    static let byteLimit = 32 << 20

    private var cache: [String: CGImage] = [:]
    /// Keys from the oldest use to the newest.
    private var order: [String] = []
    private var bytes = 0
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// The thumbnail of `file` no larger than `pixels` on its long side; nil when the file cannot be read.
    func thumbnail(of file: URL, pixels: Int) async -> CGImage? {
        let stamp = await Task.detached(priority: .userInitiated) { Self.stamp(file) }.value
        let key = "\(stamp)|\(pixels)"
        if let hit = cache[key] { touch(key); return hit }
        await acquire()
        defer { release() }
        if Task.isCancelled { return nil }
        if let hit = cache[key] { touch(key); return hit }
        guard let image = await Task.detached(priority: .userInitiated, operation: { Self.decode(file, pixels: pixels) }).value
        else { return nil }
        store(image, key)
        return image
    }

    private func acquire() async {
        if running < Self.width { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        // The newest ask goes first: it is what the grid has just scrolled to.
        if let next = waiters.popLast() { next.resume() } else { running -= 1 }
    }

    private func touch(_ key: String) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }

    private func store(_ image: CGImage, _ key: String) {
        cache[key] = image
        touch(key)
        bytes += image.bytesPerRow * image.height
        while bytes > Self.byteLimit, order.count > 1, let oldest = order.first {
            order.removeFirst()
            if let gone = cache.removeValue(forKey: oldest) { bytes -= gone.bytesPerRow * gone.height }
        }
    }

    /// The file's path, date and size: a changed file is read again.
    nonisolated static func stamp(_ file: URL) -> String {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(file.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
    }

    /// The image of the file nearest above `pixels` (an .icns holds several sizes), scaled down to `pixels`.
    nonisolated static func decode(_ file: URL, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var best = 0, bestWidth = 0
        for i in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            // The smallest image at least `pixels` wide, else the largest.
            if bestWidth < pixels ? width > bestWidth : (width >= pixels && width < bestWidth) { best = i; bestWidth = width }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, best, options as CFDictionary)
    }

    nonisolated static func physicalCores() -> Int {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 else {
            return ProcessInfo.processInfo.activeProcessorCount
        }
        return Int(cores)
    }
}

/// A choice's picture at `side` points: its thumbnail once made (a plain tile until then), its in-memory image, or a
/// dashed app symbol when there is no picture.
struct IconThumbnail: View {
    let choice: IconChoice
    let side: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else if choice.file == nil, let picture = choice.image {
                Image(nsImage: picture).resizable().interpolation(.high).scaledToFit()
            } else if choice.file != nil, !failed {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(.quaternary.opacity(0.5))
                    .padding(side * 0.08)
            } else {
                Image(systemName: "questionmark.app.dashed").resizable().scaledToFit()
                    .foregroundStyle(.tertiary).padding(side / 5)
            }
        }
        .frame(width: side, height: side)
        .task(id: "\(choice.file?.path ?? "")|\(side)|\(scale)") {
            guard let file = choice.file else { image = nil; return }
            let made = await IconThumbnails.shared.thumbnail(of: file, pixels: Int((side * scale).rounded(.up)))
            guard !Task.isCancelled else { return }
            image = made
            failed = made == nil
        }
    }
}

/// Moves through a grid of sections laid out `columns` wide: ←/→ step through the whole list, ↑/↓ keep the column
/// and cross into the section above or below.
enum IconGridNavigation {
    enum Move { case left, right, up, down }

    /// The flat index after `move` from `index`; `counts` are the sections' sizes in order.
    static func index(after move: Move, from index: Int, counts: [Int], columns: Int) -> Int {
        let total = counts.reduce(0, +)
        guard total > 0 else { return 0 }
        let index = min(max(index, 0), total - 1), columns = max(1, columns)
        switch move {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, total - 1)
        case .up, .down: break
        }
        var section = 0, start = 0
        while index >= start + counts[section] { start += counts[section]; section += 1 }
        let local = index - start, count = counts[section]
        let column = local % columns, row = local / columns, lastRow = (count - 1) / columns
        if move == .up {
            if row > 0 { return index - columns }
            var s = section - 1, sStart = start
            while s >= 0, counts[s] == 0 { s -= 1 }
            guard s >= 0 else { return index }
            sStart = counts[0..<s].reduce(0, +)
            let c = counts[s]
            return sStart + min((c - 1) / columns * columns + column, c - 1)
        }
        if row < lastRow { return start + min(local + columns, count - 1) }
        var s = section + 1
        while s < counts.count, counts[s] == 0 { s += 1 }
        guard s < counts.count else { return index }
        return counts[0..<s].reduce(0, +) + min(column, counts[s] - 1)
    }

    /// How many cells of `cell` points fit in `width` with `spacing` between them (as `GridItem.adaptive` lays them).
    static func columns(width: CGFloat, cell: CGFloat, spacing: CGFloat) -> Int {
        max(1, Int((width + spacing) / (cell + spacing)))
    }
}

/// The grid's state: the choices (read again when the folder changes), the search, the highlighted cell, and what the
/// folder's buttons do.
@MainActor @Observable
final class IconGridModel {
    var items: [IconChoice] = []
    var current = ""
    var query = ""
    /// The word of the cell the arrow keys and Return act on.
    var highlighted: String?
    /// A word to scroll to (the highlighted cell after a key, a file just added).
    var scrollTarget: String?

    @ObservationIgnored let folder: URL?
    @ObservationIgnored private let choices: @MainActor () -> [IconChoice]
    @ObservationIgnored private let value: @MainActor () -> String
    @ObservationIgnored private let onPick: @MainActor (String) -> Void
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingReload: DispatchWorkItem?

    init(choices: @escaping @MainActor () -> [IconChoice], folder: URL?, current: @escaping @MainActor () -> String,
         onPick: @escaping @MainActor (String) -> Void) {
        self.choices = choices
        self.folder = folder
        self.value = current
        self.onPick = onPick
    }

    /// Reads the choices and the current value again; the highlight stays on its word, else goes to the current one.
    func reload() {
        items = choices()
        current = value()
        if highlighted.map({ word in !items.contains { $0.word == word } }) ?? true { highlighted = current }
    }

    /// The choices matching the search, by section in their order.
    var sections: [(title: String, items: [IconChoice])] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [(title: String, items: [IconChoice])] = []
        for item in items where words.isEmpty || item.title.lowercased().contains(words) {
            if let i = result.firstIndex(where: { $0.title == item.section }) { result[i].items.append(item) }
            else { result.append((item.section, [item])) }
        }
        return result
    }

    func pick(_ word: String) {
        highlighted = word
        guard word != current else { return }
        current = word
        onPick(word)
    }

    func move(_ move: IconGridNavigation.Move, columns: Int) {
        let sections = sections
        let flat = sections.flatMap(\.items).map(\.word)
        guard !flat.isEmpty else { return }
        let from = highlighted.flatMap { flat.firstIndex(of: $0) } ?? -1
        let to = from < 0 ? 0 : IconGridNavigation.index(after: move, from: from, counts: sections.map(\.items.count),
                                                          columns: columns)
        highlighted = flat[to]
        scrollTarget = flat[to]
    }

    // MARK: The folder

    /// Shows the folder in the Finder (made first when it does not exist yet).
    func revealFolder() {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Asks for pictures and copies them into the folder.
    func addWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = Self.types
        panel.prompt = "Add"
        panel.message = "Pictures to add to the icons folder"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    /// Copies the pictures among `urls` into the folder (off the main thread), under a lowercase name of letters,
    /// digits, "-", "_" and "."; an existing name gets "-2", "-3"… The first one added is highlighted.
    func add(_ urls: [URL]) {
        guard let folder else { return }
        let pictures = urls.filter(Self.isPicture)
        guard !pictures.isEmpty else { return }
        Task {
            let added = await Task.detached(priority: .userInitiated) { Self.copy(pictures, into: folder) }.value
            reload()
            if let first = added.first, items.contains(where: { $0.word == first }) {
                highlighted = first
                scrollTarget = first
            }
        }
    }

    static let types: [UTType] = [.png, .icns, .jpeg, .heic, .tiff, UTType(filenameExtension: "icon")].compactMap { $0 }

    nonisolated static func isPicture(_ url: URL) -> Bool {
        ["png", "icns", "jpg", "jpeg", "heic", "tif", "tiff", "icon"].contains(url.pathExtension.lowercased())
    }

    /// The words (file names without extension) of the copies made.
    nonisolated static func copy(_ urls: [URL], into folder: URL) -> [String] {
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        var words: [String] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let base = safeName(url.deletingPathExtension().lastPathComponent)
            var name = base, n = 1
            while files.fileExists(atPath: folder.appendingPathComponent("\(name).\(ext)").path) { n += 1; name = "\(base)-\(n)" }
            if (try? files.copyItem(at: url, to: folder.appendingPathComponent("\(name).\(ext)"))) != nil { words.append(name) }
        }
        return words
    }

    nonisolated static func safeName(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        let mapped = String(name.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return mapped.isEmpty ? "icon" : mapped
    }

    /// Watches the folder while the grid is shown: a file added, removed or renamed there reloads the choices.
    func startWatching() {
        guard watcher == nil, let folder else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
        pendingReload?.cancel()
    }

    /// A copy of many files is many events: one reload after they stop.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

/// The picture grid: a search field and the folder's buttons above, the choices by section below, the current one
/// ringed. A click picks; the arrow keys move the highlight and Return picks it; pictures dropped on the grid are
/// added to the folder. `onPicked` is told after a pick (a popover closes).
struct IconGridView: View {
    let model: IconGridModel
    var side: CGFloat = 72
    var onPicked: () -> Void = {}
    @State private var width: CGFloat = 0
    @State private var dropping = false
    @FocusState private var focus: Focus?
    private enum Focus { case search, grid }
    private let spacing: CGFloat = 8, padding: CGFloat = 16

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .search)
                    .onKeyPress(.downArrow) { focus = .grid; return .handled }
                    .onSubmit { pickHighlighted() }
                if model.folder != nil {
                    Button { model.revealFolder() } label: { Image(systemName: "folder") }
                        .help("Show the icons folder in the Finder")
                    Button { model.addWithPanel() } label: { Image(systemName: "plus") }
                        .help("Add pictures to the icons folder (or drop them on the grid)")
                }
            }
            .padding(.horizontal, padding)
            .padding(.vertical, 10)
            Divider()
            grid
        }
        .onAppear {
            model.reload()
            model.scrollTarget = model.current
            model.startWatching()
            focus = .grid
        }
        .onDisappear { model.stopWatching() }
    }

    private var cellWidth: CGFloat { side + 20 }
    private var columns: Int {
        IconGridNavigation.columns(width: width - 2 * padding, cell: cellWidth, spacing: spacing)
    }

    private var grid: some View {
        let sections = model.sections
        let headed = Set(sections.map(\.title)).count > 1
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                    ForEach(sections, id: \.title) { section in
                        if headed {
                            Text(section.title.isEmpty ? "Other" : section.title)
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: spacing)], spacing: 10) {
                            ForEach(section.items, id: \.word) { item in
                                IconCell(item: item, side: side, selected: item.word == model.current,
                                         highlighted: item.word == model.highlighted && focus == .grid)
                                    .id(item.word)
                                    .onTapGesture { model.pick(item.word); onPicked() }
                            }
                        }
                    }
                    if sections.isEmpty {
                        Text(model.items.isEmpty ? "No pictures" : "No matches")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(padding)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: model.scrollTarget) { _, word in
                guard let word else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(word) }
                model.scrollTarget = nil
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .grid)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            switch press.key {
            case .leftArrow: model.move(.left, columns: columns)
            case .rightArrow: model.move(.right, columns: columns)
            case .upArrow: model.move(.up, columns: columns)
            case .downArrow: model.move(.down, columns: columns)
            default: pickHighlighted()
            }
            return .handled
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.folder != nil else { return false }
            model.add(urls)
            return true
        } isTargeted: { dropping = $0 && model.folder != nil }
    }

    private func pickHighlighted() {
        guard let word = model.highlighted ?? model.sections.first?.items.first?.word else { return }
        model.pick(word)
        onPicked()
    }
}

private struct IconCell: View {
    let item: IconChoice
    let side: CGFloat
    let selected: Bool
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 4) {
            IconThumbnail(choice: item, side: side)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                        .fill(highlighted ? Color.accentColor.opacity(0.15) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                )
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .frame(width: side + 20)
        .contentShape(Rectangle())
        .help(item.word)
    }
}

/// The settings row's control: the current picture and its name, and Choose… that opens the grid in a popover.
struct IconRowControl: View {
    @Environment(SettingsModel.self) private var model
    @Environment(\.isEnabled) private var isEnabled
    let key: String
    let choices: @MainActor () -> [IconChoice]
    let folder: URL?
    @State private var choice: IconChoice?
    @State private var grid: IconGridModel?

    var body: some View {
        let value = model.value(key)
        HStack(spacing: 8) {
            IconThumbnail(choice: choice ?? IconChoice(word: value), side: 22)
            Text(IconChoice.title(of: value))
                .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 140, alignment: .trailing)
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .help(value)
            Button("Choose…") {
                grid = IconGridModel(choices: choices, folder: folder, current: { model.value(key) },
                                     onPick: { model.set(key, $0) })
            }
            .popover(isPresented: Binding(get: { grid != nil }, set: { if !$0 { grid = nil } }), arrowEdge: .bottom) {
                if let grid {
                    IconGridView(model: grid) { self.grid = nil }
                        .frame(width: 520, height: 420)
                }
            }
        }
        // Only the current picture is looked up here; the grid reads the rest when it opens.
        .task(id: value) { choice = choices().first { $0.word == value } }
    }
}
