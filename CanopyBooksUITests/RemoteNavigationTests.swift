import XCTest

/// Drives the Siri Remote through the player's interactions, attaching a screenshot at each step.
@MainActor
final class RemoteNavigationTests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testBrowseAndJumpToSentence() {
        // Sentence 3 runs 10.9–27.3 s, long enough that playback won't move on mid-test.
        launch(at: 12)
        waitForFocus(on: sentence(3))
        snapshot("1 following playback")

        remote.press(.down)
        remote.press(.down)
        waitForFocus(on: sentence(5))
        snapshot("2 browsing")

        // Sentence 5 starts at 35.1 s: clicking it should move playback there and keep it there.
        remote.press(.select)
        sleep(2)
        XCTAssertGreaterThanOrEqual(elapsed(), 35, "Selecting a sentence should seek to it")
        XCTAssertTrue(sentence(5).hasFocus, "Focus should stay on the sentence now being read")
        snapshot("3 jumped to sentence 5")

        remote.press(.down)
        waitForFocus(on: sentence(6))
        remote.press(.menu)
        waitForFocus(on: sentence(5))

        // Clicking while following playback pauses and resumes, like the system player.
        remote.press(.select)
        sleep(1)
        let paused = elapsed()
        sleep(2)
        XCTAssertEqual(elapsed(), paused, "Click on the playing sentence should pause")
        remote.press(.select)
        sleep(2)
        XCTAssertGreaterThan(elapsed(), paused, "Second click should resume")

        // A click straight after moving (mid-animation) still jumps. Sentence 7 starts at 67.8 s.
        remote.press(.down)
        remote.press(.down)
        remote.press(.select)
        sleep(2)
        XCTAssertGreaterThanOrEqual(elapsed(), 67, "Quick click should still seek")
        waitForFocus(on: sentence(7))
    }

    func testControlsScrubAndSpeed() {
        launch(at: 12)
        waitForFocus(on: sentence(3))

        remote.press(.left)
        let scrubber = app.buttons["scrubber"]
        let controls = ["scrubber", "skipBack", "playPause", "skipForward", "speed"].map { app.buttons[$0] }
        XCTAssertTrue(controls.contains { $0.hasFocus }, "Left from the text should focus a control")
        focus(scrubber, pressing: .up)
        snapshot("4 controls")

        // Right on the idle scrubber leaves for the text column.
        remote.press(.right)
        waitForFocus(on: sentence(3))
        remote.press(.left)
        focus(scrubber, pressing: .up)

        // Scrubbing: click, move forward 30 s, and the scrubber keeps focus throughout.
        let before = elapsed()
        remote.press(.select)
        remote.press(.right)
        remote.press(.right)
        remote.press(.right)
        XCTAssertTrue(scrubber.hasFocus, "Scrubbing should keep focus on the bar")
        snapshot("5 scrubbing")
        remote.press(.select)
        waitForFocus(on: scrubber)
        sleep(1)
        XCTAssertGreaterThanOrEqual(elapsed() - before, 29, "Scrubbing +30 s should seek forward")

        // The system-styled buttons don't report focus to XCUITest, so step by layout:
        // down from the bar's centre lands on skip-forward, and speed is to its right.
        remote.press(.down)
        sleep(1)
        remote.press(.right)
        sleep(1)
        remote.press(.select)
        sleep(1)
        snapshot("6 speed menu")
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
        snapshot("7 speed set")

        // Back from the controls returns to the text, on whichever sentence is being read.
        remote.press(.menu)
        let focusedSentence = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sentence-'"))
            .element(matching: NSPredicate(format: "hasFocus == true"))
        waitForFocus(on: focusedSentence)
    }

    // MARK: - Helpers

    private func launch(at seconds: Double) {
        app.launchArguments = ["-startAt", String(seconds)]
        app.launch()
    }

    /// Playback position read from the scrub bar's accessibility value ("m:ss" or "h:mm:ss").
    private func elapsed() -> Double {
        let text = app.buttons["scrubber"].value as? String ?? ""
        return text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    private func sentence(_ index: Int) -> XCUIElement {
        app.buttons["sentence-\(index)"]
    }

    private func waitForFocus(on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(hasFocus(element, within: 5), "\(element) never got focus", file: file, line: line)
    }

    private func hasFocus(_ element: XCUIElement, within timeout: TimeInterval) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }

    /// Presses a direction until the element has focus, letting focus settle between presses.
    private func focus(_ element: XCUIElement, pressing direction: XCUIRemote.Button, limit: Int = 4,
                       file: StaticString = #filePath, line: UInt = #line) {
        var presses = 0
        while !hasFocus(element, within: 1), presses < limit {
            remote.press(direction)
            presses += 1
        }
        XCTAssertTrue(element.hasFocus, "Couldn't focus \(element)", file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
