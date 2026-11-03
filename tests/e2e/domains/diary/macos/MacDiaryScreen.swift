import Foundation
import XCTest

final class MacDiaryScreen {
    private let driver: MacAppDriver
    private var editor: XCUIElement { driver.app.textViews["日記の本文"] }
    private var saveButton: XCUIElement { driver.app.buttons["保存"] }

    init(driver: MacAppDriver) { self.driver = driver }

    func waitUntilLoaded() throws {
        try driver.wait("the diary editor must be available") { self.editor.exists && self.editor.isEnabled }
    }

    func content() throws -> String {
        guard editor.exists, let value = editor.value as? String else {
            throw E2EError.condition("Cannot read the diary editor; refusing to assume it is empty.")
        }
        return value
    }

    /// Inspect future dates through the UI; never overwrite an occupied entry.
    func selectUnusedDate() throws -> String {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for offset in 1...14 {
            let date = formatter.string(from: calendar.date(byAdding: .day, value: offset, to: start)!)
            driver.app.buttons["翌日"].click()
            try waitUntilLoaded()
            // WebKit exposes aria-pressed calendar buttons as native checkboxes.
            let selected = driver.app.checkBoxes["\(date)の日記"]
            try driver.wait("the intended date must be selected") { selected.exists && self.isSelected(selected) }
            try waitUntilLoaded()
            if try content().isEmpty { return date }
        }
        throw E2EError.condition("No unused diary date found in the next 14 days; nothing was overwritten.")
    }

    func selectDate(_ date: String) throws {
        let day = driver.app.checkBoxes["\(date)の日記"]
        if !day.exists {
            driver.app.buttons["次の月"].click()
        }
        try driver.wait("the test date must be available in the calendar") { day.exists && day.isHittable }
        day.click()
        try waitUntilLoaded()
        try driver.wait("the test date must be selected") { self.isSelected(day) }
    }

    private func isSelected(_ day: XCUIElement) -> Bool {
        day.value as? String == "1" || (day.value as? NSNumber)?.boolValue == true
    }

    func replaceContent(_ text: String) throws {
        try waitUntilLoaded()
        let frame = editor.frame
        guard !frame.isEmpty, !frame.isInfinite,
              driver.app.windows.firstMatch.frame.contains(frame) else {
            throw E2EError.condition("The diary editor must be fully inside the app window before typing.")
        }
        // Filled WKWebView textareas can have no default hit point in XCTest.
        // Resolve the actual editor by its accessible name, then click its center.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        if !text.isEmpty {
            let clipboard = try MacClipboard()
            do {
                try clipboard.writeText(text)
                editor.typeKey("v", modifierFlags: .command)
                try driver.wait("the pasted input must match exactly") { (try? self.content()) == text }
            } catch {
                try clipboard.restore()
                throw error
            }
            try clipboard.restore()
        }
        try driver.wait("the editor must contain the exact input") { (try? self.content()) == text }
    }

    func save() throws {
        try driver.wait("Save must be enabled") { self.saveButton.isEnabled }
        saveButton.click()
        try driver.wait("the save must finish successfully") {
            self.editor.isEnabled && !self.saveButton.isEnabled && self.driver.app.staticTexts["保存済み"].exists
        }
    }
}
