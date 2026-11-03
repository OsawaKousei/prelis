import XCTest

final class MacTimerScreen {
    private let driver: MacAppDriver
    private var picker: XCUIElement { driver.app.popUpButtons["音声を選択"] }
    private var preview: XCUIElement { driver.app.buttons["試聴"] }

    init(driver: MacAppDriver) { self.driver = driver }

    func openSettings() throws {
        try driver.wait("Timer must finish loading") { self.driver.app.buttons["開始"].exists }
        if picker.exists && picker.isHittable { return }
        // WebKit exposes the summary through AXTitle, not AXLabel. Timer has
        // exactly one disclosure; require that structure rather than guessing text.
        let disclosures = driver.app.webViews.disclosureTriangles
        try driver.wait("the timer sound disclosure must be available") { disclosures.count == 1 && disclosures.element.isHittable }
        let disclosure = disclosures.element
        disclosure.click()
        try driver.wait("the sound picker must be available") { self.picker.exists && self.picker.isHittable && self.picker.isEnabled }
    }

    func selectedName() throws -> String {
        guard let name = picker.value as? String, !name.isEmpty else {
            throw E2EError.condition("Cannot read the original sound selection")
        }
        return name
    }

    func checkUniqueOption(_ name: String) throws {
        picker.click()
        let count = driver.app.menuItems.matching(identifier: name).count
        driver.app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        guard count == 1 else { throw E2EError.condition("The existing sound selection cannot be restored unambiguously") }
    }

    func select(_ name: String) throws {
        picker.click()
        let options = driver.app.menuItems.matching(identifier: name)
        guard options.count == 1 else {
            driver.app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            throw E2EError.condition("Expected one sound named \(name)")
        }
        options.element.click()
        try driver.wait("the selected sound must be ready") { (try? self.selectedName()) == name && self.preview.isEnabled }
    }

    func importSound(path: String, name: String) throws {
        // WebKit exposes the empty file input by its native title instead of
        // the HTML label. Require exactly one to avoid choosing another button.
        let uploads = driver.app.webViews.buttons.matching(identifier: "no file selected")
        try driver.wait("the sound upload control must be available") { uploads.count == 1 && uploads.element.isHittable }
        let upload = uploads.element
        upload.click()
        let panel = driver.app.dialogs["open-panel"]
        try driver.wait("the native open panel must be available") { panel.exists }
        let openButtons = panel.buttons.matching(NSPredicate(format: "title IN %@", ["Open", "開く"]))
        try driver.wait("the native Open button must be available") { openButtons.count == 1 }
        let open = openButtons.element
        panel.typeKey("g", modifierFlags: [.command, .shift])
        panel.typeText(path)
        panel.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        try driver.wait("the fixture must be selectable") { open.exists && open.isEnabled }
        open.click()
        try driver.wait("the imported sound must be selected and playable", timeout: 25) {
            (try? self.selectedName()) == name && self.preview.isEnabled
        }
    }

    func playPreview() throws {
        try driver.wait("Preview must be enabled") { self.preview.isEnabled }
        preview.click()
    }

    func setOneMinute() throws {
        let minutes = driver.app.textFields["時間（分）"]
        try driver.wait("the timer duration input must be available") { minutes.exists && minutes.isEnabled }
        minutes.click()
        minutes.typeKey("a", modifierFlags: .command)
        minutes.typeText("1")
        try driver.wait("the timer must be set to one minute") { minutes.value as? String == "1" }
    }

    func startAndWaitForCompletion() throws {
        let start = driver.app.buttons["開始"]
        try driver.wait("Start must be enabled") { start.isEnabled }
        start.click()
        try driver.wait("the timer must be running") { self.driver.app.buttons["一時停止"].exists }
        try driver.wait("the real one-minute timer must complete", timeout: 75) {
            self.driver.app.staticTexts["完了 — リセットしてください"].exists
        }
    }

    func reset() throws {
        driver.app.buttons["リセット"].click()
        try driver.wait("Reset must return the timer to its stopped state") { self.driver.app.buttons["開始"].isEnabled }
    }

    func removeFixture(name: String, original: String) throws {
        try reset()
        // Import may have failed before creating an option; inspect without choosing anything.
        picker.click()
        let exists = driver.app.menuItems.matching(identifier: name).count == 1
        driver.app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        guard exists else { return }
        if try selectedName() != name { try select(name) }
        driver.app.buttons["選択中の音声を削除"].click()
        try driver.wait("the test sound must be removed") { (try? self.selectedName()) == "音声なし" }
        if original != "音声なし" { try select(original) }
    }
}
