import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case generate = "Generate"
    case ask = "Ask AI"
    case cv = "CV"
    case coverLetter = "Cover letter"
    case resources = "Resources"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cv: return "doc.text"
        case .coverLetter: return "envelope"
        case .generate: return "sparkles"
        case .ask: return "bubble.left.and.bubble.right"
        case .resources: return "link"
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
                Label(item.rawValue, systemImage: item.systemImage).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                SidebarFooter()
            }
        } detail: {
            Group {
                switch selection {
                case .cv: CVView()
                case .coverLetter: CoverLetterView()
                case .generate: GenerateView()
                case .ask: AskView()
                case .resources: ResourcesView()
                case .settings: SettingsView()
                case .none: Text("Select a section").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
    }
}

private struct SidebarFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text("Farhad's CV AutoFill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
