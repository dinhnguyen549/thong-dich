import SwiftUI
import UIKit

/// Entry view used by the app target.
public struct RootView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        HomeView()
            // Views read `model.settings`, so they redraw (in the new language) when it changes.
        .environment(model)
        .preferredColorScheme(model.settings.appearance.colorScheme)
        .tint(Theme.accent(model.settings.mode))
        .task { await model.onLaunch() }
        .onChange(of: scenePhase) { _, phase in
            // iOS forbids GPU work in the background. Translation pauses as soon as the app
            // leaves the screen and catches up when it returns; listening never stops.
            model.setActive(phase == .active)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.handleMemoryWarning()
        }
        .onOpenURL { url in
            // A recording shared from Voice Memos / Files ("Open in Thông Dịch")
            model.openedRecording = url
        }
    }
}
