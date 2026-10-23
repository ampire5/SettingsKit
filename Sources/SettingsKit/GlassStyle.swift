import AppKit
import SwiftUI

/// How much Liquid Glass the settings window gets.
public enum SettingsStyle: String, Sendable {
    /// The stock sidebar (full height, edge to edge on macOS 27), opaque cards with a hairline.
    case plain
    /// A floating sidebar panel of glass, inset from the window edges, and cards of regular glass over a softly
    /// tinted window. With Reduce Transparency the system draws the glass opaque.
    case glass
}

extension EnvironmentValues {
    @Entry var settingsStyle: SettingsStyle = .plain
    /// The window's width (0 until measured): the glass background is laid out over the whole window.
    @Entry var settingsWindowWidth: CGFloat = 0
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

/// The window background under the glass: the window colour with a faint plum→teal diagonal tint, so the glass
/// has something to refract while text keeps its contrast. One gradient over the whole window: the sidebar
/// column (at the window's leading edge) and the page (at its trailing edge) each draw their part of it, so
/// the two meet without a seam. Opaque, so it also covers the split view's own sidebar glass.
struct GlassPageBackground: View {
    /// The window edge the view lies against; it spans the window's full height.
    let edge: HorizontalEdge
    @Environment(\.colorScheme) private var scheme
    @Environment(\.settingsWindowWidth) private var windowWidth

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let window = max(windowWidth, width)
                let x = edge == .leading ? 0 : window - width
                LinearGradient(colors: dark
                                   ? [Color(red: 0.36, green: 0.22, blue: 0.48).opacity(0.30),
                                      Color(red: 0.10, green: 0.30, blue: 0.42).opacity(0.22)]
                                   : [Color(red: 0.62, green: 0.48, blue: 0.86).opacity(0.16),
                                      Color(red: 0.36, green: 0.68, blue: 0.86).opacity(0.14)],
                               startPoint: UnitPoint(x: -x / width, y: 0),
                               endPoint: UnitPoint(x: (window - x) / width, y: 1))
            }
        }
    }
}

extension View {
    /// The card's surface: opaque fill and hairline (plain) or regular glass (glass).
    @ViewBuilder func cardSurface(_ style: SettingsStyle) -> some View {
        switch style {
        case .glass:
            glassEffect(.regular, in: .rect(cornerRadius: 12))
        case .plain:
            background(SettingsColors.cardFill, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    /// The page's background for the style.
    @ViewBuilder func pageBackground(_ style: SettingsStyle) -> some View {
        switch style {
        case .glass: background { GlassPageBackground(edge: .trailing).ignoresSafeArea() }
        case .plain: background(Color(nsColor: .windowBackgroundColor))
        }
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
                .background { Color.clear.glassEffect(.regular, in: panel).padding(inset).ignoresSafeArea() }
                .background { GlassPageBackground(edge: .leading).ignoresSafeArea() }
        }
    }
}

extension SettingsStyle {
    /// Secondary text (descriptions, folder notes, units). On glass the hierarchical `.secondary` is drawn vibrant
    /// and fell to 3.0:1 (dark) and 2.6:1 (light); a fixed 75 % of the label colour measures 5.0:1 and 4.8:1.
    var secondaryText: AnyShapeStyle {
        switch self {
        case .plain: AnyShapeStyle(.secondary)
        case .glass: AnyShapeStyle(Color.primary.opacity(0.75))
        }
    }
}
