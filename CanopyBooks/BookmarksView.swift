import SwiftUI

/// Full-screen list of a book's bookmarks, grouped by chapter. Click one to jump there;
/// press and hold to remove it.
struct BookmarksView: View {
    let model: AudiobookPlayer
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark",
                        description: Text("Press and hold a sentence to bookmark it.")
                    )
                } else {
                    List {
                        ForEach(chapters, id: \.chapter) { group in
                            Section(model.chapters[group.chapter].title) {
                                ForEach(group.sentences, id: \.self, content: row)
                            }
                        }
                    }
                    .frame(maxWidth: 1400)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Bookmarks")
            // The cover is otherwise see-through; reuse the player's backdrop, dimmed for reading.
            .background {
                ArtworkBackground(image: model.cover)
                    .overlay(Color.black.opacity(0.35))
                    .ignoresSafeArea()
            }
        }
    }

    private func row(_ sentence: Int) -> some View {
        Button {
            dismiss()
            onSelect(sentence)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 40) {
                Text(model.sentences[sentence].text)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(timeIntoChapter(sentence))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                model.toggleBookmark(sentence: sentence)
            }
        }
        .accessibilityIdentifier("bookmark-\(sentence)")
    }

    /// Bookmarked sentences in book order, grouped by chapter.
    private var chapters: [(chapter: Int, sentences: [Int])] {
        let sentences = model.bookmarks.compactMap(model.sentenceIndex(for:))
        return Dictionary(grouping: sentences) { model.sentences[$0].chapter }
            .sorted { $0.key < $1.key }
            .map { (chapter: $0.key, sentences: $0.value.sorted()) }
    }

    private func timeIntoChapter(_ sentence: Int) -> String {
        let chapter = model.chapters[model.sentences[sentence].chapter]
        let seconds = max(0, model.sentences[sentence].start - chapter.start).rounded(.down)
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }
}
