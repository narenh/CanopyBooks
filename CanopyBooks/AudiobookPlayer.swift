import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Owns playback and publishes which sentence is being read.
/// Now Playing (Control Center, the iPhone remote, Siri) comes from MPNowPlayingSession.
@Observable
final class AudiobookPlayer {
    /// Highlight a sentence slightly before its first word so the scroll animation lands on time.
    static let highlightLead = 0.15
    static let skipInterval = 15.0

    let chapter: Chapter
    let sentences: [Sentence]
    let cover: UIImage
    let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    private(set) var activeIndex: Int?
    private(set) var isPlaying = false
    /// Whole seconds, so progress views redraw once a second rather than on every tick.
    private(set) var elapsed = 0.0
    private(set) var duration = 0.0
    private(set) var rate: Float = 1

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private let nowPlaying: MPNowPlayingSession
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var hasStarted = false

    init(chapter: Chapter) {
        self.chapter = chapter
        sentences = chapter.loadSentences()
        cover = UIImage(named: chapter.coverAsset) ?? UIImage()

        let asset = AVURLAsset(url: chapter.audioURL)
        let item = AVPlayerItem(asset: asset)
        item.nowPlayingInfo = Self.nowPlayingInfo(for: chapter, cover: cover)
        player = AVPlayer(playerItem: item)

        nowPlaying = MPNowPlayingSession(players: [player])
        nowPlaying.automaticallyPublishesNowPlayingInfo = true
        registerRemoteCommands()

        // Fires on the interval, and also whenever time jumps or playback starts/stops.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.sync(to: time.seconds) }
        }

        Task {
            duration = (try? await asset.load(.duration).seconds) ?? 0
        }
    }

    /// Starts playback the first time it's called. Call once the scene is active: playback
    /// started during the launch animation can be suspended by the system.
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        nowPlaying.becomeActiveIfPossible(completion: nil)
        #if DEBUG
        // `xcrun simctl launch <device> com.naren.CanopyBooks -startAt 1000` starts mid-chapter.
        let startAt = UserDefaults.standard.double(forKey: "startAt")
        if startAt > 0 { seek(to: startAt) }
        #endif
        player.play()
    }

    func togglePlayPause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func skip(by seconds: Double) {
        seek(to: player.currentTime().seconds + seconds)
    }

    func seek(to seconds: Double) {
        let upperBound = duration > 0 ? duration : .greatestFiniteMagnitude
        let time = CMTime(seconds: min(max(0, seconds), upperBound), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Jumps to the start of a sentence and plays from there.
    func play(sentence index: Int) {
        // A hair early so the first word isn't clipped; still inside `highlightLead`.
        seek(to: sentences[index].start - 0.1)
        activeIndex = index
        player.play()
    }

    func setRate(_ newRate: Float) {
        player.defaultRate = newRate
        if player.rate != 0 { player.rate = newRate }
        rate = newRate
    }

    private func sync(to seconds: Double) {
        let index = sentences.index(at: seconds + Self.highlightLead)
        if index != activeIndex { activeIndex = index }
        let whole = seconds.rounded(.down)
        if whole != elapsed { elapsed = whole }
        let playing = player.rate != 0
        if playing != isPlaying { isPlaying = playing }
    }

    // MARK: - Now Playing

    private func registerRemoteCommands() {
        let commands = nowPlaying.remoteCommandCenter
        Self.register(commands.playCommand) { [weak self] _ in self?.player.play() }
        Self.register(commands.pauseCommand) { [weak self] _ in self?.player.pause() }
        Self.register(commands.togglePlayPauseCommand) { [weak self] _ in self?.togglePlayPause() }

        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        Self.register(commands.skipForwardCommand) { [weak self] _ in self?.skip(by: Self.skipInterval) }
        Self.register(commands.skipBackwardCommand) { [weak self] _ in self?.skip(by: -Self.skipInterval) }

        Self.register(commands.changePlaybackPositionCommand, value: {
            ($0 as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
        }) { [weak self] position in self?.seek(to: position) }

        commands.changePlaybackRateCommand.supportedPlaybackRates = speeds.map { NSNumber(value: $0) }
        Self.register(commands.changePlaybackRateCommand, value: {
            Double(($0 as? MPChangePlaybackRateCommandEvent)?.playbackRate ?? 1)
        }) { [weak self] rate in self?.setRate(Float(rate)) }
    }

    /// MediaPlayer may call handlers off the main thread, so this is nonisolated and hops to
    /// the main actor with just the value it needs from the event.
    nonisolated private static func register(
        _ command: MPRemoteCommand,
        value: @escaping @Sendable (MPRemoteCommandEvent) -> Double = { _ in 0 },
        perform: @escaping @MainActor @Sendable (Double) -> Void
    ) {
        command.isEnabled = true
        command.addTarget { event in
            let value = value(event)
            Task { @MainActor in perform(value) }
            return .success
        }
    }

    private static func nowPlayingInfo(for chapter: Chapter, cover: UIImage) -> [String: Any] {
        [
            MPMediaItemPropertyTitle: "Chapter \(chapter.number): \(chapter.title)",
            MPMediaItemPropertyAlbumTitle: chapter.bookTitle,
            MPMediaItemPropertyArtist: chapter.author,
            MPMediaItemPropertyArtwork: artwork(cover),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }

    /// The request handler runs on a background queue, so it must not inherit main-actor isolation.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
