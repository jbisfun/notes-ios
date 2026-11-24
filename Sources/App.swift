import FossifyCommons
import Observation
import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case customizeColors
    case about
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []
    /// A text file opened in the app ("Open in…" / the launcher) waiting to be imported.
    var openURL: URL?

    func push(_ r: Route) { path.append(r) }
}

/// The whole app as one view: the standalone app's window content, and what
/// the launcher presents. `openURL` is a text file handed over by the launcher.
public struct NotesRoot: View {
    @State private var store = NotesStore.shared
    @State private var router = Router()
    private let openURL: URL?

    public init(openURL: URL? = nil) {
        self.openURL = openURL
    }

    public var body: some View {
        RootView()
            .environment(store)
            .environment(router)
            .environment(Config.shared)
            .fossifyTheme()
            .onOpenURL { url in router.openURL = url }
            .onAppear { if let openURL { router.openURL = openURL } }
    }
}

struct RootView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        NavigationStack(path: $router.path) {
            MainView()
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .settings: SettingsView()
                        case .customizeColors: CustomizeColorsView()
                        case .about: AboutView(app: .notes)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .paletteBackground()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .toast($store.toast)
        .appLock()
    }
}
