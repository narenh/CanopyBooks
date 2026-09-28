import AVKit
import SwiftUI

/// The system player, with the lyrics-style view hosted in its content overlay.
/// AVKit supplies the transport bar, Siri Remote gestures, skip, and the playback-speed menu
/// (`speeds` defaults to `AVPlaybackSpeed.systemDefaultSpeeds`).
struct PlayerContainer: UIViewControllerRepresentable {
    let model: AudiobookPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        // The overlay already shows title/author under the artwork, like Apple Music.
        controller.transportBarIncludesTitleView = false

        let overlay = UIHostingController(rootView: NowPlayingView(model: model))
        overlay.view.backgroundColor = .clear
        // Display only; remote input goes to the player controls.
        overlay.view.isUserInteractionEnabled = false
        if let container = controller.contentOverlayView {
            controller.addChild(overlay)
            overlay.view.frame = container.bounds
            overlay.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(overlay.view)
            overlay.didMove(toParent: controller)
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
