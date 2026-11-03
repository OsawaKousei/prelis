import XCTest

final class DiaryPersistenceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSavedEntrySurvivesRestart() throws {
        let driver = try MacAppDriver()
        let diary = MacDiaryScreen(driver: driver)
        guard let text = ProcessInfo.processInfo.environment["PRELIS_E2E_DIARY_TEXT"], !text.isEmpty else {
            throw E2EError.configuration("The diary fixture is missing.")
        }
        var testDate: String?
        var mayContainTestInput = false
        // XCTest runs teardown blocks in reverse registration order. Keep final
        // termination separate so an interaction failure in cleanup cannot skip it.
        addTeardownBlock {
            if driver.launchedByTest, driver.app.state != .notRunning {
                try driver.terminate()
            }
        }
        addTeardownBlock {
            guard driver.launchedByTest else { return }
            // Retain the original failure; report cleanup failure as an additional failure.
            do {
                if mayContainTestInput, let date = testDate {
                    if driver.app.state == .notRunning { try driver.launch() }
                    try driver.openDiary()
                    try diary.selectDate(date)
                    let current = try diary.content()
                    guard current.isEmpty || current == text else {
                        throw E2EError.condition("Cleanup stopped: diary content differs from the fixture at \(date).")
                    }
                    if current == text {
                        try diary.replaceContent("")
                        try diary.save()
                    }
                }
            } catch {
                XCTFail("Cleanup failed: \(error)")
            }
        }

        do {
            try driver.launch()
            try driver.openDiary()
            try diary.waitUntilLoaded()
            testDate = try diary.selectUnusedDate()
            XCTAssertEqual(try diary.content(), "")
            XCTContext.runActivity(named: "Test date: \(testDate!)") { _ in }
            mayContainTestInput = true
            let inputStarted = ProcessInfo.processInfo.systemUptime
            try diary.replaceContent(text)
            let inputDuration = ProcessInfo.processInfo.systemUptime - inputStarted
            XCTContext.runActivity(named: String(format: "Diary input: %d characters in %.2f seconds (paste)", text.count, inputDuration)) { _ in }
            try diary.save()
            driver.attachScreenshot("diary-saved")

            try driver.terminate()
            try driver.launch()
            try driver.openDiary()
            try diary.waitUntilLoaded()
            try diary.selectDate(testDate!)
            XCTAssertEqual(try diary.content(), text, "Saved input must survive a full app restart.")
            driver.attachScreenshot("diary-after-restart")
        } catch {
            let hierarchy = XCTAttachment(string: driver.app.windows.firstMatch.debugDescription)
            hierarchy.name = "ui-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            throw error
        }
    }
}
