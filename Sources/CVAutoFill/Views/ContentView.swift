import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case generate = "Generate"
    case ask = "Ask AI"
    case cv = "CV"
    case coverLetter = "Cover letter"
    case resources = "Resources"
    case jobs = "Jobs"
    case prompts = "Prompts"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cv: return "doc.text"
        case .coverLetter: return "envelope"
        case .generate: return "sparkles"
        case .ask: return "bubble.left.and.bubble.right"
        case .resources: return "link"
        case .jobs: return "briefcase"
        case .prompts: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SidebarItem? = .generate

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .foregroundStyle(
                        selection == item
                            ? Color(hex: state.settings.menuTextColorHex)
                            : Color.primary
                    )
                    .tag(item)
                    // The sidebar's native row-selection highlight follows the
                    // system accent color and ignores both .tint() and
                    // .listItemTint() here — .listRowBackground is what
                    // actually replaces it with a custom color.
                    .listRowBackground(
                        selection == item
                            ? Color(hex: state.settings.accentColorHex)
                            : Color.clear
                    )
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                SidebarFooter()
            }
            .modifier(GlassPanelBackground(enabled: state.settings.windowStyle == .glass))
        } detail: {
            HStack(spacing: 0) {
                Group {
                    switch selection {
                    case .cv: CVView()
                    case .coverLetter: CoverLetterView()
                    case .generate: GenerateView()
                    case .ask: AskView()
                    case .resources: ResourcesView()
                    case .jobs: JobsView()
                    case .prompts: PromptsView()
                    case .settings: SettingsView()
                    case .none: Text("Select a section").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .modifier(GlassPanelBackground(enabled: state.settings.windowStyle == .glass))

                if state.cliTerminalVisible {
                    Divider()
                    CLITerminalPanel()
                }
            }
        }
    }
}

// Background-only glass, applied per-panel (sidebar and detail separately) —
// NOT wrapping the whole NavigationSplitView in one glass shape, which
// previously broke layout (see CVAutoFillApp.swift). Each panel already has
// its own bounded frame here, so glassEffect just paints behind it instead
// of taking part in the split view's own layout negotiation.
//
// .background(alignment:content:) ignores safe areas on every edge by
// default, so the glass rectangle would otherwise extend up under the
// window's title bar / toolbar strip and visibly change it. Explicitly
// ignoring only the leading/trailing/bottom edges (and NOT .top) keeps the
// glass stopped right below the title bar, leaving it untouched.
private struct GlassPanelBackground: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, #available(macOS 26.0, *) {
            content.background {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Rectangle())
                    .ignoresSafeArea(edges: [.leading, .trailing, .bottom])
            }
        } else {
            content
        }
    }
}

private struct SidebarFooter: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 6) {
            Text("~$\(String(format: "%.4f", totalEstimatedSpend)) spent")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var totalEstimatedSpend: Double {
        Provider.allCases.reduce(0) { total, provider in
            total + state.usageEntries(for: provider).reduce(0) { $0 + $1.estimatedCost }
        }
    }
}
