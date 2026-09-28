import XCTest

/// Drives the Siri Remote through the player's interactions, attaching a screenshot at each step.
///
/// The system-styled circle buttons don't report focus to XCUITest, so play/pause focus is
/// checked by clicking and confirming playback toggled.
@MainActor
final class RemoteNavigationTests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testFocusMovesBetweenControlsAndText() {
        // Sentence 5 runs 26.2–42.6 s into the book, long enough that playback won't move on mid-test.
        launch(at: 28)
        snapshot("1 launch")
        // Pausing also keeps sentence 3 current for the rest of the test.
        assertClickTogglesPlayback("Focus should start on play/pause")

        // Up to the bar, right into the text: lands on the sentence being read.
        enterText()
        waitForFocus(on: sentence(5))
        snapshot("2 current sentence focused")

        // Left from the text reaches the end of the button row (speed), then steps along it.
        remote.press(.left)
        sleep(1)
        assertSpeedMenuOpens("Left from the text should land on the speed button")
        remote.press(.left)
        remote.press(.left)
        sleep(1)
        assertClickTogglesPlayback("Two more lefts should reach play/pause")
        assertClickTogglesPlayback("Clicking again should pause")

        // Idle on the current sentence: focus drifts back to play/pause after 6 s.
        enterText()
        waitForFocus(on: sentence(5))
        sleep(8)
        XCTAssertFalse(sentence(5).hasFocus, "The highlight shouldn't stay on an idle sentence")
        assertClickTogglesPlayback("Idle focus should return to play/pause")
        assertClickTogglesPlayback("Clicking again should pause")

        // Back from the text returns to play/pause.
        enterText()
        waitForFocus(on: sentence(5))
        remote.press(.menu)
        assertClickTogglesPlayback("Back from the text should return to play/pause")
    }

    func testBrowseAndJumpToSentence() {
        launch(at: 28)
        enterText()
        waitForFocus(on: sentence(5))

        remote.press(.down)
        remote.press(.down)
        waitForFocus(on: sentence(7))
        snapshot("3 browsing")

        // Sentence 7 starts at 50.4 s: clicking it moves playback there and focus stays with it.
        remote.press(.select)
        sleep(2)
        XCTAssertGreaterThanOrEqual(elapsed(), chapterTime(50), "Selecting a sentence should seek to it")
        XCTAssertTrue(sentence(7).hasFocus, "Focus should stay on the sentence now being read")
        snapshot("4 jumped to sentence 5")

        // Clicking the highlighted current sentence restarts it.
        sleep(2)
        remote.press(.select)
        sleep(1)
        XCTAssertLessThan(elapsed(), chapterTime(52.9), "Clicking the current sentence should restart it")

        // A click straight after moving (mid-animation) still jumps. Sentence 9 starts at 83.0 s.
        remote.press(.down)
        remote.press(.down)
        remote.press(.select)
        sleep(2)
        XCTAssertGreaterThanOrEqual(elapsed(), chapterTime(82.5), "Quick click should still seek")
        waitForFocus(on: sentence(9))

        // Browsing idle: after 12 s focus returns to play/pause.
        remote.press(.down)
        waitForFocus(on: sentence(10))
        sleep(14)
        XCTAssertFalse(sentence(10).hasFocus, "Idle browsing should hand focus back")
        assertClickTogglesPlayback("Idle browsing should return to play/pause")
    }

    func testScrubAndSpeed() {
        launch(at: 28)
        remote.press(.up)
        waitForFocus(on: scrubber)
        snapshot("5 controls")

        // Scrubbing: click, move forward 30 s, and the scrubber keeps focus throughout.
        let before = elapsed()
        remote.press(.select)
        remote.press(.right)
        remote.press(.right)
        remote.press(.right)
        XCTAssertTrue(scrubber.hasFocus, "Scrubbing should keep focus on the bar")
        snapshot("6 scrubbing")
        remote.press(.select)
        waitForFocus(on: scrubber)
        sleep(1)
        XCTAssertGreaterThanOrEqual(elapsed() - before, 29, "Scrubbing +30 s should seek forward")

        // Right into the text, then left lands on speed at the end of the button row.
        remote.press(.right)
        waitForFocus(on: focusedSentence)
        remote.press(.left)
        sleep(1)
        remote.press(.select)
        sleep(1)
        snapshot("7 speed menu")
        let labelled = NSPredicate(format: "label != ''")
        let options = app.cells.otherElements.matching(labelled).allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(options, ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "1.75×", "2×"])
        // The menu opens on its first item; 1.5× is four down.
        for _ in 0..<4 {
            remote.press(.down)
        }
        let focusedOption = app.cells.element(matching: NSPredicate(format: "hasFocus == true"))
        XCTAssertEqual(focusedOption.otherElements.matching(labelled).firstMatch.label, "1.5×")
        remote.press(.select)
        sleep(1)
        let start = elapsed()
        sleep(6)
        let gained = elapsed() - start
        XCTAssertGreaterThanOrEqual(gained, 8, "6 s at 1.5× should advance ~9 s, got \(gained)")

        // Back from the controls falls through to the system and leaves the app.
        remote.press(.menu)
        let left = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue),
            object: app
        )
        XCTAssertEqual(XCTWaiter().wait(for: [left], timeout: 5), .completed, "Back from the controls should leave the app")
    }

    func testChapterMenu() {
        launch(at: 28)
        // From play/pause, the chapter button is two to the left.
        remote.press(.left)
        sleep(1)
        remote.press(.left)
        sleep(1)
        remote.press(.select)
        sleep(1)
        snapshot("8 chapter menu")
        let labelled = NSPredicate(format: "label != ''")
        let options = app.cells.otherElements.matching(labelled).allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Array(options.prefix(3)), ["The Hobbit", "An Unexpected Party", "Chapter II"])

        // The menu opens on its first item; Chapter II is two down.
        remote.press(.down)
        remote.press(.down)
        let focusedOption = app.cells.element(matching: NSPredicate(format: "hasFocus == true"))
        XCTAssertEqual(focusedOption.otherElements.matching(labelled).firstMatch.label, "Chapter II")
        remote.press(.select)
        sleep(2)
        // Chapter II's first sentence is 564 in the book; the bar restarts at the chapter.
        XCTAssertTrue(sentence(564).exists, "Chapter II's text should be showing")
        XCTAssertLessThan(elapsed(), 5, "Playback should be at the start of Chapter II")
        snapshot("9 chapter II")
    }

    func testSentenceTallerThanScreen() {
        // Sentence 4605 (28073.6–28129.8 s) is about two screens tall. Start on 4602 and pause so
        // playback stays put.
        launch(at: 28048)
        assertClickTogglesPlayback("Focus should start on play/pause")
        enterText()
        waitForFocus(on: sentence(4602))

        // Browse down through the tall sentence and past it.
        for next in 4603...4605 {
            remote.press(.down)
            waitForFocus(on: sentence(next))
        }
        snapshot("10 browsing to a tall sentence")
        remote.press(.down)
        waitForFocus(on: sentence(4606))
        remote.press(.up)
        waitForFocus(on: sentence(4605))

        // Clicking it plays it; moving down from it still reaches the next sentence.
        remote.press(.select)
        sleep(3)
        snapshot("11 reading a tall sentence")
        remote.press(.down)
        waitForFocus(on: sentence(4606))
    }

    func testResumesWhereItLeftOff() {
        // Play from inside sentence 5 (26.2–42.6 s), quit, and relaunch without a start time.
        launch(at: 30)
        sleep(3)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(scrubber.waitForExistence(timeout: 10))
        sleep(2)
        // It resumes from the start of that sentence.
        let resumed = elapsed()
        XCTAssertTrue(
            (chapterTime(26)...chapterTime(31)).contains(resumed),
            "Expected to resume near the start of sentence 5, got \(resumed) s into the chapter"
        )
        enterText()
        waitForFocus(on: sentence(5))
    }

    // MARK: - Helpers

    private var focusedSentence: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sentence-'"))
            .element(matching: NSPredicate(format: "hasFocus == true"))
    }

    private var scrubber: XCUIElement { app.buttons["scrubber"] }

    private func sentence(_ index: Int) -> XCUIElement {
        app.buttons["sentence-\(index)"]
    }

    private func launch(at seconds: Double) {
        app.launchArguments = ["-startAt", String(seconds)]
        app.launch()
        XCTAssertTrue(scrubber.waitForExistence(timeout: 10))
        sleep(1)
    }

    /// From play/pause: up to the bar, then right into the text.
    private func enterText() {
        remote.press(.up)
        waitForFocus(on: scrubber)
        remote.press(.right)
    }

    /// Clicks, checks the speed menu opened, then closes it with Back.
    private func assertSpeedMenuOpens(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        remote.press(.select)
        let menuItem = app.cells.firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3), message, file: file, line: line)
        remote.press(.menu)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: menuItem)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 3), .completed, "Back should close the menu", file: file, line: line)
        sleep(1)
    }

    /// Clicks and checks the play/pause button flipped between "Play" and "Pause".
    private func assertClickTogglesPlayback(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let playPause = app.buttons["playPause"]
        let expected = playPause.label == "Pause" ? "Play" : "Pause"
        remote.press(.select)
        let toggled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: playPause)
        XCTAssertEqual(XCTWaiter().wait(for: [toggled], timeout: 3), .completed, message, file: file, line: line)
    }

    /// The scrub bar shows time into the chapter; chapter 1 starts 18.32 s into the book.
    private func chapterTime(_ bookTime: Double) -> Double {
        bookTime - 18.32
    }

    /// Chapter position read from the scrub bar's accessibility value ("m:ss" or "h:mm:ss").
    private func elapsed() -> Double {
        let text = scrubber.value as? String ?? ""
        return text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    private func waitForFocus(on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        let result = XCTWaiter().wait(for: [focused], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element) never got focus", file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
