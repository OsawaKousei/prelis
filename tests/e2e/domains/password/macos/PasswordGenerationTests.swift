import XCTest

final class PasswordGenerationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testConditionsGenerationAndCopy() throws {
        let driver = try MacAppDriver(captureLabel: "password")
        let screen = MacPasswordScreen(driver: driver)
        let clipboard = try MacClipboard()
        addTeardownBlock {
            if driver.launchedByTest, driver.app.state != .notRunning { try driver.terminate() }
        }
        addTeardownBlock { try clipboard.restore() }
        do {
            try driver.launch()
            try driver.openFeature("Password")
            try screen.waitUntilLoaded()
            try screen.assertEmptyResult()
            let allSets = ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", "0123456789", "!@#$%^&*_-+=?"]
            let first = try screen.generatePassword(length: 16, requiredSets: allSets)
            try screen.copyPassword(first, clipboard: clipboard)
            driver.attachScreenshot("password-generated-and-copied")

            try screen.setCheckbox("間違えやすい文字を除く", selected: true)
            _ = try screen.generatePassword(length: 16, requiredSets: allSets, excluded: "IOl01")
            driver.attachScreenshot("password-ambiguous-excluded")

            for name in ["大文字", "小文字", "記号"] { try screen.setCheckbox(name, selected: false) }
            for length in [4, 8, 12, 16] {
                try screen.setLength(length)
                _ = try screen.generatePassword(length: length, requiredSets: ["23456789"])
            }
            driver.attachScreenshot("password-numbers-only")
            try screen.setCheckbox("数字", selected: false)
            try screen.assertGenerationDisabled()
            driver.attachScreenshot("password-no-types-disabled")
        } catch {
            driver.attachScreenshot("password-failed")
            let hierarchy = XCTAttachment(string: driver.app.windows.firstMatch.debugDescription)
            hierarchy.name = "password-ui-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            throw error
        }
    }
}
