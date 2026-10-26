import SwiftUI

/// A page: section headings and cards in a scroll view, and below them Reset Page to Defaults (on a page with keys).
/// The sidebar's sub-section dot follows the scrolling; a sub-section clicked in the sidebar is scrolled to and keeps
/// the dot until the user scrolls. A page stays built while another is open (`SettingsUIState.keptPages`); only the
/// open one moves the dot and answers sub-section clicks.
///
/// A page is built in pieces of a few lines, one piece per run loop turn (`PagePieces`): it shows at once and fills in
/// below, and input gets through between the pieces. Built in one go, a page took 30–150 ms of the main thread on an
/// M4 Max (LoupeBench settings), three times that on an Intel Mac; one card at a time still 20–70 ms.
struct PageView: View {
    @Environment(SettingsUIState.self) private var ui
    @Environment(SettingsModel.self) private var model
    @Environment(\.settingsStyle) private var style
    let page: SettingsPage
    let isOpen: Bool
    @State private var sectionFrames: [String: CGRect] = [:]
    @State private var geometry: ScrollGeometry?
    @State private var position = ScrollPosition(edge: .top)
    /// The clicked sub-section; holds the dot (even where the page cannot scroll that far) until a user scroll.
    @State private var pinned: String?
    @State private var confirmingReset = false
    /// How many of the page's lines (`PagePieces.lines`, in reading order) are built.
    @State private var built: Int

    init(page: SettingsPage, isOpen: Bool) {
        self.page = page
        self.isOpen = isOpen
        _built = State(initialValue: PagePieces.firstPiece)
    }

    private var lineCount: Int { page.sections.reduce(0) { $0 + $1.cards.reduce(0) { $0 + PagePieces.lines(in: $1) } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(builtSections.enumerated()), id: \.element.section.id) { _, item in
                    let section = item.section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                        VStack(spacing: 16) {
                            ForEach(item.cards.indices, id: \.self) {
                                CardView(card: section.cards[$0], limit: item.cards[$0])
                            }
                        }
                    }
                    .id(section.title)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: {
                        sectionFrames[section.title] = $0
                        updateCurrentSection()
                    }
                }
                if !page.keys.isEmpty, built >= lineCount { resetButton }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .environment(\.settingsPageID, page.id)
        .pageBackground(style)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, new in
            geometry = new
            updateCurrentSection()
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting || phase == .decelerating {
                pinned = nil
                updateCurrentSection()
            }
        }
        .onAppear { buildNextPiece() }
        .onChange(of: isOpen) { _, open in
            // Back on a kept page: the dot follows where it was left.
            if open { pinned = nil; updateCurrentSection() }
        }
        .onChange(of: ui.scrollRequest, initial: true) { _, request in
            guard isOpen, let request else { return }
            built = lineCount
            pinned = request
            ui.currentSection = request
            // Right after a page switch the sections are not laid out yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.25)) { position.scrollTo(id: request, anchor: .top) }
                if ui.scrollRequest == request { ui.scrollRequest = nil }
            }
        }
    }

    /// The sections that have a built line, each with the number of lines built of each of its cards that has one
    /// (`Int.max` for a complete card, so it also shows the lines of its open chevrons).
    private var builtSections: [(section: SettingsSection, cards: [Int])] {
        var left = built
        var result: [(section: SettingsSection, cards: [Int])] = []
        for section in page.sections where left > 0 {
            var cards: [Int] = []
            for card in section.cards where left > 0 {
                let lines = PagePieces.lines(in: card)
                cards.append(left >= lines ? .max : left)
                left -= min(left, lines)
            }
            result.append((section, cards))
        }
        return result
    }

    /// Builds the next piece in the next run loop turn, after this one has been drawn, until the page is complete.
    private func buildNextPiece() {
        guard built < lineCount else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
            guard built < lineCount else { PagePieces.pieceDone(); return }
            let lines = PagePieces.nextPiece()
            built = min(built + lines, lineCount)
            buildNextPiece()
        }
    }

    /// Asks first: the page's changed settings go back to their defaults at once (`SettingsModel.resetPage`).
    private var resetButton: some View {
        let changed = model.modifiedKeys(in: page).count
        return HStack {
            Spacer()
            Button("Reset Page to Defaults…") { confirmingReset = true }
                .disabled(changed == 0)
                .help(changed == 0 ? "Every setting on this page is at its default" : "Changed on this page: \(changed)")
        }
        .confirmationDialog("Reset “\(page.title)” to its defaults?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetPage(page) }
        } message: {
            Text(changed == 1 ? "1 changed setting goes back to its default."
                              : "\(changed) changed settings go back to their defaults.")
        }
    }

    /// IINA's rule: the first section while near the top, the last at the bottom, otherwise the last section
    /// that starts above one third of the viewport.
    private func updateCurrentSection() {
        guard isOpen, let g = geometry else { return }
        let titles = page.sections.map(\.title)
        var current = titles.first ?? ""
        let top = g.contentInsets.top
        if let pinned {
            current = pinned
        } else if g.contentOffset.y + top <= 40 {
            current = titles.first ?? ""
        } else if g.visibleRect.maxY >= g.contentSize.height - 40 {
            current = titles.last ?? ""
        } else {
            // `.scrollView` frames start below the toolbar inset; IINA probes at 1/3 of the whole viewport.
            let probe = (g.containerSize.height + top) * 0.33 - top
            for title in titles where (sectionFrames[title]?.minY ?? .infinity) <= probe { current = title }
        }
        if ui.currentSection != current { ui.currentSection = current }
    }
}

/// How big a piece of a page is built per run loop turn: as many lines as fit `budget` ms of the main thread at the
/// cost per line measured on this Mac (the CPU time from one piece to the next, so other work in between only makes
/// the pieces smaller). A line is a row of a card or one of its nested rows; an open chevron's lines come with it.
@MainActor
enum PagePieces {
    /// Main-thread time one piece may take: input waits at most this long, plus a frame's drawing.
    static let budget = 10.0
    /// The lowest cost per line the estimate goes to (an M4 Max builds a plain row in ~2 ms).
    static let minPerLine = 2.0
    /// ms of main-thread CPU per line, as measured; starts high (an Intel Mac's 15–25 ms) and learns.
    private(set) static var perLine = 20.0
    /// The piece in flight: when it was asked for and how many lines it has.
    private static var pending: (cpu: Double, lines: Int)?

    /// The most lines in one piece: cheap pieces (nested rows, plain switches) teach a low cost per line, and a
    /// piece sized by it that then meets heavy rows (pop-ups, fields) took 50–120 ms on an M4 Max.
    static let maxLines = 4

    /// The lines shown at once when a page is first opened: half a piece, as the page itself is made in that turn too.
    static var firstPiece: Int { min(maxLines / 2, max(1, Int(budget / 2 / perLine))) }

    private static var linesInBudget: Int { min(maxLines, max(1, Int(budget / perLine))) }

    /// The lines of the next piece; the previous piece's cost (if one is in flight) updates the estimate.
    static func nextPiece() -> Int {
        let now = threadCPU()
        if let pending { learn(ms: now - pending.cpu, lines: pending.lines) }
        let lines = linesInBudget
        pending = (now, lines)
        return lines
    }

    /// The last piece of a page is drawn: its cost updates the estimate.
    static func pieceDone() {
        if let pending { learn(ms: threadCPU() - pending.cpu, lines: pending.lines) }
        pending = nil
    }

    private static func learn(ms: Double, lines: Int) {
        guard lines > 0, ms > 0 else { return }
        // A piece whose turn the machine spent elsewhere (another window, a sleep) says little: cap its weight.
        let measured = min(ms / Double(lines), 100)
        perLine = max(minPerLine, perLine * 0.6 + measured * 0.4)
    }

    /// A card's lines: its rows and their nested rows (not the rows behind chevrons). A `.custom` row (a table, say)
    /// counts as `customLines`, so it comes in a piece of its own.
    static func lines(in card: SettingsCard) -> Int {
        func count(_ row: SettingsRow) -> Int {
            if case .custom = row.kind { return customLines }
            return 1 + row.nested.reduce(0) { $0 + count($1) }
        }
        return card.rows.reduce(0) { $0 + count($1) }
    }

    /// What a `.custom` row counts as.
    static let customLines = 10

    private static func threadCPU() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1_000_000
    }
}
