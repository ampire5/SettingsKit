import SwiftUI

/// A page: section headings and cards in a scroll view, and below them Reset Page to Defaults (on a page with keys).
/// The sidebar's sub-section dot follows the scrolling; a sub-section clicked in the sidebar is scrolled to and keeps
/// the dot until the user scrolls. A page stays built while another is open (`SettingsUIState.keptPages`); only the
/// open one moves the dot and answers sub-section clicks.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(page.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                        VStack(spacing: 16) {
                            ForEach(section.cards.indices, id: \.self) { CardView(card: section.cards[$0]) }
                        }
                    }
                    .id(section.title)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: {
                        sectionFrames[section.title] = $0
                        updateCurrentSection()
                    }
                }
                if !page.keys.isEmpty { resetButton }
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
        .onChange(of: isOpen) { _, open in
            // Back on a kept page: the dot follows where it was left.
            if open { pinned = nil; updateCurrentSection() }
        }
        .onChange(of: ui.scrollRequest, initial: true) { _, request in
            guard isOpen, let request else { return }
            pinned = request
            ui.currentSection = request
            // Right after a page switch the sections are not laid out yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.25)) { position.scrollTo(id: request, anchor: .top) }
                if ui.scrollRequest == request { ui.scrollRequest = nil }
            }
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
