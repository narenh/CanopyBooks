import AVFoundation
import AVKit
import Observation
import UIKit

/// Owns the AVPlayer and publishes which sentence is currently being read.
/// Transport (play/pause, scrubbing, skip, playback speed, Now Playing) is left to AVKit.
@Observable
final class AudiobookPlayer {
    /// Highlight a sentence slightly before its first word so the scroll animation lands on time.
    static let highlightLead = 0.1

    let chapter: Chapter
    let sentences: [Sentence]
    let cover: UIImage
    let backdrop: UIImage
    @ObservationIgnored let player: AVPlayer

    private(set) var activeIndex: Int?
    private(set) var isPlaying = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var hasStarted = false

    init(chapter: Chapter) {
        self.chapter = chapter
        sentences = chapter.loadSentences()
        cover = UIImage(named: chapter.coverAsset) ?? UIImage()
        backdrop = cover.blurredBackdrop() ?? cover

        let item = AVPlayerItem(url: chapter.audioURL)
        item.externalMetadata = Self.metadata(for: chapter, cover: cover)
        player = AVPlayer(playerItem: item)

        // Fires on the interval, and also whenever time jumps or playback starts/stops.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.sync(to: time.seconds) }
        }
    }

    /// Starts playback the first time it's called. Call once the scene is active: AVKit pauses
    /// anything started while the launch animation is still running.
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        #if DEBUG
        // `xcrun simctl launch <device> com.naren.CanopyBooks -startAt 1000` starts mid-chapter.
        let startAt = UserDefaults.standard.double(forKey: "startAt")
        if startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        #endif
        player.play()
    }

    private func sync(to seconds: Double) {
        let index = sentences.index(at: seconds + Self.highlightLead)
        if index != activeIndex { activeIndex = index }
        let playing = player.rate != 0
        if playing != isPlaying { isPlaying = playing }
    }

    /// Shown by AVKit in the transport bar title, the Info panel, and system Now Playing.
    private static func metadata(for chapter: Chapter, cover: UIImage) -> [AVMetadataItem] {
        func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol, dataType: String? = nil) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.extendedLanguageTag = "und"
            if let dataType { item.dataType = dataType }
            return item
        }
        var items = [
            item(.commonIdentifierTitle, "Chapter \(chapter.number): \(chapter.title)" as NSString),
            item(.iTunesMetadataTrackSubTitle, "\(chapter.bookTitle) · \(chapter.author)" as NSString),
            item(.commonIdentifierAlbumName, chapter.bookTitle as NSString),
            item(.commonIdentifierArtist, chapter.author as NSString),
        ]
        if let jpeg = cover.jpegData(compressionQuality: 0.9) {
            items.append(item(.commonIdentifierArtwork, jpeg as NSData, dataType: kCMMetadataBaseDataType_JPEG as String))
        }
        return items
    }
}
