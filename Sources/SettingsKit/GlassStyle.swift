import AppKit
import SwiftUI

/// How much Liquid Glass the settings window gets.
public enum SettingsStyle: String, Sendable {
    /// The stock sidebar (full height, edge to edge on macOS 27), opaque cards with a hairline.
    case plain
    /// An inset glass sidebar with a dark veil. Settings cards use the same opaque surface in both styles.
    case glass
}

extension EnvironmentValues {
    @Entry var settingsStyle: SettingsStyle = .plain
    /// The id of the page a row is on (set by `PageView`).
    @Entry var settingsPageID = ""
}

/// Metrics of the glass style's sidebar panel.
enum GlassMetrics {
    /// Gap between the sidebar panel and the window edges (and the page).
    static let sidebarInset: CGFloat = 8
    /// Corner radius of the sidebar panel, concentric with the window's.
    static let sidebarRadius: CGFloat = 18
}

extension View {
    /// A neutral card with a quiet hairline in either appearance.
    func settingsCardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return background(SettingsColors.cardFill, in: shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.08)) }
    }

    /// The sidebar column's look. Glass: the column's content (search field, page list) inside an own rounded
    /// panel of regular glass, inset from the window edges and the page; the window background around it covers
    /// the split view's stock sidebar glass, which has no public switch on macOS 27. Plain: the stock sidebar.
    @ViewBuilder func sidebarSurface(_ style: SettingsStyle) -> some View {
        switch style {
        case .plain: self
        case .glass:
            let inset = GlassMetrics.sidebarInset
            let panel = RoundedRectangle(cornerRadius: GlassMetrics.sidebarRadius)
            padding(.horizontal, inset).padding(.bottom, inset)
                // Rows scrolled under the search field and the title bar stay inside the panel.
                .mask { panel.padding(inset).ignoresSafeArea() }
                .background {
                    panel.fill(.black.opacity(0.30))
                        .glassEffect(.regular, in: panel)
                        .padding(inset).ignoresSafeArea()
                }
                .environment(\.colorScheme, .dark)
                .background { Color(white: 0.12).ignoresSafeArea() }
        }
    }
}
