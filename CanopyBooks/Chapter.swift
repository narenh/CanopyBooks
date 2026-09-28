import Foundation

/// One aligned sentence from the forced-alignment JSON. Extra fields in the file
/// (confidence scores etc.) are ignored.
nonisolated struct Sentence: Decodable, Sendable {
    let start: Double
    let end: Double
    let text: String
    let para: Int
}

/// Everything needed to play one chapter. For the test run, all assets live in the app bundle.
nonisolated struct Chapter: Sendable {
    let bookTitle: String
    let author: String
    let number: Int
    let title: String
    let audioResource: String
    let audioExtension: String
    let sentencesResource: String
    let coverAsset: String

    static let hobbitChapter1 = Chapter(
        bookTitle: "The Hobbit",
        author: "J. R. R. Tolkien",
        number: 1,
        title: "An Unexpected Party",
        audioResource: "hobbit_ch1",
        audioExtension: "wav",
        sentencesResource: "hobbit_ch1_sentences",
        coverAsset: "Cover"
    )

    var audioURL: URL {
        guard let url = Bundle.main.url(forResource: audioResource, withExtension: audioExtension) else {
            fatalError("Missing \(audioResource).\(audioExtension) in app bundle")
        }
        return url
    }

    func loadSentences() -> [Sentence] {
        guard let url = Bundle.main.url(forResource: sentencesResource, withExtension: "json") else {
            fatalError("Missing \(sentencesResource).json in app bundle")
        }
        do {
            return try JSONDecoder().decode([Sentence].self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not decode \(sentencesResource).json: \(error)")
        }
    }
}

nonisolated extension [Sentence] {
    /// Index of the last sentence that has started by `time`, or nil before the first one.
    func index(at time: Double) -> Int? {
        var low = 0, high = count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if self[mid].start <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }
}
