import Foundation

/// One spoken sentence and its time range in the book's audio.
nonisolated struct Sentence: Sendable {
    let start: Double
    let end: Double
    let text: String
    let para: Int
    /// Index of the chapter this sentence belongs to.
    let chapter: Int
}

/// The spoken sentences of one EPUB section, e.g. "Chapter II".
nonisolated struct Chapter: Sendable {
    let section: Int
    let title: String
    /// Indices into the book's sentences.
    var sentences: Range<Int>
    var start: Double
    /// When the next chapter starts, so the pause before a heading belongs to the chapter before it.
    var end: Double

    var timeRange: ClosedRange<Double> { start...max(start, end) }
}

/// A bundled book: audio, forced-alignment JSON and cover art.
nonisolated struct Audiobook: Sendable {
    let title: String
    let author: String
    let audioResource: String
    let audioExtension: String
    let alignmentResource: String
    let coverAsset: String

    static let hobbit = Audiobook(
        title: "The Hobbit",
        author: "J. R. R. Tolkien",
        audioResource: "The Hobbit",
        audioExtension: "mp3",
        alignmentResource: "hobbit.alignment.rerun",
        coverAsset: "Cover"
    )

    var audioURL: URL {
        guard let url = Bundle.main.url(forResource: audioResource, withExtension: audioExtension) else {
            fatalError("Missing \(audioResource).\(audioExtension) in app bundle")
        }
        return url
    }

    /// The spoken sentences grouped into chapters. Sentences the narrator doesn't read (contents,
    /// footnote markers…) have no timing and are left out.
    func loadText() -> (sentences: [Sentence], chapters: [Chapter]) {
        guard let url = Bundle.main.url(forResource: alignmentResource, withExtension: "json") else {
            fatalError("Missing \(alignmentResource).json in app bundle")
        }
        let alignment: Alignment
        do {
            alignment = try JSONDecoder().decode(Alignment.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not decode \(alignmentResource).json: \(error)")
        }

        let sectionTitles = Dictionary(alignment.sections.map { ($0.index, $0.title) }) { first, _ in first }
        var sentences: [Sentence] = []
        var chapters: [Chapter] = []
        for line in alignment.sentences {
            guard let start = line.start, let end = line.end else { continue }
            if chapters.last?.section != line.sec {
                // Untitled sections are named by their first spoken line.
                let title = Self.displayTitle(sectionTitles[line.sec] ?? nil) ?? Self.displayTitle(line.text) ?? self.title
                chapters.append(Chapter(section: line.sec, title: title, sentences: sentences.count..<sentences.count, start: start, end: end))
            }
            sentences.append(Sentence(start: start, end: end, text: line.text, para: line.para, chapter: chapters.count - 1))
            chapters[chapters.count - 1].sentences = chapters[chapters.count - 1].sentences.lowerBound..<sentences.count
            chapters[chapters.count - 1].end = end
        }
        for i in chapters.indices.dropLast() {
            chapters[i].end = chapters[i + 1].start
        }
        if !chapters.isEmpty { chapters[0].start = 0 }
        return (sentences, chapters)
    }

    /// EPUB headings are often set in capitals ("AN UNEXPECTED PARTY").
    private static func displayTitle(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw == raw.uppercased() ? raw.capitalized : raw
    }
}

/// The alignment file's shape; only the fields the player needs.
private nonisolated struct Alignment: Decodable {
    nonisolated struct Section: Decodable {
        let index: Int
        let title: String?
    }

    nonisolated struct Line: Decodable {
        let sec: Int
        let para: Int
        let text: String
        let start: Double?
        let end: Double?
    }

    let sections: [Section]
    let sentences: [Line]
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
