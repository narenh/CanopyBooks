import SwiftUI

@main
struct CanopyBooksApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AudiobookPlayer(chapter: .hobbitChapter1)

    var body: some Scene {
        WindowGroup {
            PlayerScreen(model: model)
                .onChange(of: scenePhase, initial: true) {
                    if scenePhase == .active { model.startIfNeeded() }
                }
        }
    }
}
