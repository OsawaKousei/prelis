import XCTest

final class TimerSoundTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPreviewCompletionAndResetAudio() throws {
        let driver = try MacAppDriver(captureLabel: "timer-setup")
        let timer = MacTimerScreen(driver: driver)
        guard let fixture = ProcessInfo.processInfo.environment["PRELIS_E2E_SOUND_PATH"] else {
            throw E2EError.configuration("The audible timer fixture is missing")
        }
        let name = URL(fileURLWithPath: fixture).lastPathComponent
        var original: String?
        var importStarted = false
        addTeardownBlock {
            if driver.launchedByTest, driver.app.state != .notRunning { try driver.terminate() }
        }
        addTeardownBlock {
            if importStarted, let original, driver.app.state != .notRunning {
                try timer.openSettings()
                try timer.removeFixture(name: name, original: original)
            }
        }
        do {
            try driver.launch()
            try driver.openFeature("Timer")
            try timer.openSettings()
            original = try timer.selectedName()
            try timer.checkUniqueOption(original!)
            importStarted = true
            try timer.importSound(path: fixture, name: name)
            try driver.beginCapture("timer-preview")
            guard let capture = driver.capture else { throw E2EError.configuration("Audio capture is required for this test") }
            let preview = try capture.mark("preview-request")
            try timer.playPreview()
            try capture.waitUntil(preview + 3)
            try capture.stop()

            try timer.setOneMinute()
            try driver.beginCapture("timer-completion")
            _ = try capture.mark("timer-start-request")
            try timer.startAndWaitForCompletion()
            let completed = try capture.mark("timer-completed")
            try capture.waitUntil(completed + 2)
            driver.attachScreenshot("timer-completed")
            try timer.reset()
            let reset = try capture.mark("timer-reset")
            try capture.waitUntil(reset + 2)
            try capture.stop()
        } catch {
            driver.attachScreenshot("timer-failed")
            let attachment = XCTAttachment(string: driver.app.windows.firstMatch.debugDescription)
            attachment.name = "timer-ui-hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
            let panels = XCTAttachment(string: driver.app.dialogs.debugDescription)
            panels.name = "timer-dialog-hierarchy"
            panels.lifetime = .keepAlways
            add(panels)
            throw error
        }
    }
}
