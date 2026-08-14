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
                .modifier(AppWindowGlass(style: state.settings.buttonStyle))
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

// "Glass" is macOS 26's Liquid Glass material — both apply the same way:
// the whole window's content sits on a glass background (SwiftUI's
// View.glassEffect(_:in:)), and every button uses the glass button style
// (PrimitiveButtonStyle.glass). Both need macOS 26.0+ and fall back to the
// normal look automatically on older macOS.
private struct AppWindowGlass: ViewModifier {
    let style: ButtonStyleChoice

    func body(content: Content) -> some View {
        switch style {
        case .normal:
            content
        case .glass:
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: Rectangle())
            } else {
                content
            }
        }
    }
}

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
