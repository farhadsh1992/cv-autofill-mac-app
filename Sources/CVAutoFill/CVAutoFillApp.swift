import SwiftUI

@main
struct CVAutoFillApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 620)
                .tint(Color(hex: state.settings.accentColorHex))
                .preferredColorScheme(colorScheme(for: state.settings.appearanceMode))
                .modifier(AppButtonStyle(style: state.settings.buttonStyle))
        }
        .defaultSize(width: 1000, height: 720)
        .windowResizability(.contentMinSize)
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// "Glass" is macOS 26's Liquid Glass button material (SwiftUI's
// PrimitiveButtonStyle.glass, macOS 26.0+) — falls back to the normal
// bordered/automatic style on older macOS.
private struct AppButtonStyle: ViewModifier {
    let style: ButtonStyleChoice

    func body(content: Content) -> some View {
        switch style {
        case .normal:
            content.buttonStyle(.automatic)
        case .glass:
            if #available(macOS 26.0, *) {
                content.buttonStyle(.glass)
            } else {
                content.buttonStyle(.automatic)
            }
        }
    }
}
