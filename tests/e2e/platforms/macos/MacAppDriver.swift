import AppKit
import XCTest

enum E2EError: Error {
    case configuration(String)
    case condition(String)
}

/// Only operations shared by multiple domains belong here.
final class MacAppDriver {
    let app: XCUIApplication
    let appURL: URL
    let bundleIdentifier: String
    private(set) var launchedByTest = false

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PRELIS_E2E_APP_PATH"],
              let identifier = environment["PRELIS_E2E_BUNDLE_ID"] else {
            throw E2EError.configuration("Run through scripts/macos/test-e2e.sh --app /path/to/PrelisDesktop.app")
        }
        appURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        bundleIdentifier = identifier
        app = XCUIApplication(url: appURL)
    }

    func launch() throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            throw E2EError.condition("The target app is already running. Close it before starting the test.")
        }
        app.launch()
        launchedByTest = true
        try wait("the selected app must be running") {
            NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleIdentifier).contains {
                $0.bundleURL?.resolvingSymlinksInPath() == self.appURL
            }
        }
        app.activate()
        try wait("the selected app must be in the foreground") { self.app.state == .runningForeground }
    }

    func terminate() throws {
        app.terminate()
        try wait("the app must terminate") { self.app.state == .notRunning }
        launchedByTest = false
    }

    func openDiary() throws {
        // The landing page also has a Diary button; scope this query to navigation.
        let button = app.webViews.groups["アプリ"].buttons["Diary"]
        try wait("Diary navigation must be available") { button.exists && button.isHittable }
        button.click()
    }

    func wait(_ description: String, timeout: TimeInterval = 15, until condition: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            throw E2EError.condition(description)
        }
    }

    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}
