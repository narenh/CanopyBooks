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

    let book: Audiobook
    let sentences: [Sentence]
    let chapters: [Chapter]
    let cover: UIImage
    let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    /// Sorted by position in the book.
    private(set) var bookmarks: [Bookmark] = [] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(bookmarks), forKey: "bookmarks.\(book.id)")
        }
    }
    private(set) var activeIndex: Int?
    /// The chapter containing the sentence being read.
    private(set) var chapterIndex = 0
    private(set) var isPlaying = false
    /// Whole seconds, so progress views redraw once a second rather than on every tick.
    private(set) var elapsed = 0.0
    private(set) var duration = 0.0
    private(set) var rate: Float = 1

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private let nowPlaying: MPNowPlayingSession
    @ObservationIgnored private let artwork: MPMediaItemArtwork
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var hasStarted = false

    var chapter: Chapter { chapters[chapterIndex] }

    /// Where this book was left off, saved as playback moves.
    private var savedPosition: Double {
        get { UserDefaults.standard.double(forKey: "position.\(book.id)") }
        set { UserDefaults.standard.set(newValue, forKey: "position.\(book.id)") }
    }

    init(book: Audiobook) {
        self.book = book
        (sentences, chapters) = book.loadText()
        cover = UIImage(named: book.coverAsset) ?? UIImage()
        artwork = Self.artwork(cover)
        if let saved = UserDefaults.standard.data(forKey: "bookmarks.\(book.id)") {
            bookmarks = (try? JSONDecoder().decode([Bookmark].self, from: saved)) ?? []
        }

        let asset = AVURLAsset(url: book.audioURL)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))

        nowPlaying = MPNowPlayingSession(players: [player])
        nowPlaying.automaticallyPublishesNowPlayingInfo = true
        updateNowPlayingInfo()
        registerRemoteCommands()

        // The speed chosen for this book last time; `play()` uses the player's default rate.
        let savedRate = UserDefaults.standard.float(forKey: "speed.\(book.id)")
        if speeds.contains(savedRate) {
            rate = savedRate
            player.defaultRate = savedRate
        }

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
        // Resume at the start of the sentence that was playing, rather than mid-word.
        if let index = sentences.index(at: savedPosition) {
            seek(to: sentences[index].start - 0.1)
            setActive(index)
        }
        #if DEBUG
        // `xcrun simctl launch <device> com.naren.CanopyBooks -startAt 1000` starts 1000 s in.
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
        setActive(index)
        player.play()
    }

    /// Jumps to the first sentence of a chapter.
    func play(chapter index: Int) {
        play(sentence: chapters[index].sentences.lowerBound)
    }

    // MARK: - Bookmarks

    var bookmarkedSentences: Set<Int> {
        Set(bookmarks.compactMap(sentenceIndex(for:)))
    }

    func sentenceIndex(for bookmark: Bookmark) -> Int? {
        sentences.index(at: bookmark.time + 0.001)
    }

    func toggleBookmark(sentence index: Int) {
        if bookmarkedSentences.contains(index) {
            bookmarks.removeAll { sentenceIndex(for: $0) == index }
        } else {
            bookmarks.append(Bookmark(time: sentences[index].start, created: .now))
            bookmarks.sort { $0.time < $1.time }
        }
    }

    func setRate(_ newRate: Float) {
        player.defaultRate = newRate
        if player.rate != 0 { player.rate = newRate }
        rate = newRate
        UserDefaults.standard.set(newRate, forKey: "speed.\(book.id)")
    }

    private func sync(to seconds: Double) {
        setActive(sentences.index(at: seconds + Self.highlightLead))
        let whole = seconds.rounded(.down)
        if whole != elapsed {
            elapsed = whole
            // Not before playback starts: the player reports 0 before the saved position is restored.
            if hasStarted { savedPosition = seconds }
        }
        let playing = player.rate != 0
        if playing != isPlaying {
            isPlaying = playing
            // No screensaver while listening; paused, the usual idle timeout applies.
            UIApplication.shared.isIdleTimerDisabled = playing
        }
    }

    private func setActive(_ index: Int?) {
        guard index != activeIndex else { return }
        activeIndex = index
        let chapter = index.map { sentences[$0].chapter } ?? 0
        if chapter != chapterIndex {
            chapterIndex = chapter
            updateNowPlayingInfo()
        }
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

    /// Published automatically by the session; the title follows the current chapter.
    private func updateNowPlayingInfo() {
        player.currentItem?.nowPlayingInfo = [
            MPMediaItemPropertyTitle: chapter.title,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyArtwork: artwork,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }

    /// The request handler runs on a background queue, so it must not inherit main-actor isolation.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
