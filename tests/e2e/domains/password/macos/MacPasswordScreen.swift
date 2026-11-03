import XCTest

final class MacPasswordScreen {
    private let driver: MacAppDriver
    private var result: XCUIElement { driver.app.textFields["生成したパスワード"] }
    private var generate: XCUIElement { driver.app.buttons["パスワードを生成"] }
    private var copy: XCUIElement { driver.app.buttons["コピー"] }

    init(driver: MacAppDriver) { self.driver = driver }

    func waitUntilLoaded() throws {
        try driver.wait("Password must finish loading") { self.result.exists && self.generate.exists && self.copy.exists }
    }

    func assertEmptyResult() throws {
        try driver.wait("Changed conditions must clear the result and disable Copy") {
            self.result.value as? String == "" && !self.copy.isEnabled
        }
    }

    private func checked(_ element: XCUIElement) throws -> Bool {
        guard let value = element.value else { throw E2EError.condition("Cannot read the selected password condition") }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String, ["0", "1"].contains(string) { return string == "1" }
        throw E2EError.condition("Unexpected password condition value")
    }

    func setCheckbox(_ name: String, selected: Bool) throws {
        let options = driver.app.webViews.checkBoxes.matching(NSPredicate(format: "title BEGINSWITH %@", name))
        try driver.wait("The password checkbox must be unique: \(name)") { options.count == 1 && options.element.isHittable }
        let option = options.element
        if try checked(option) != selected {
            option.click()
            try driver.wait("The password checkbox must update: \(name)") { (try? self.checked(option)) == selected }
            try assertEmptyResult()
        }
    }

    func setLength(_ length: Int) throws {
        // WebKit inserts whitespace between the number and Japanese unit in AXTitle.
        let options = driver.app.radioButtons.matching(NSPredicate(format: "title MATCHES %@", "^\(length)\\s*文字$"))
        try driver.wait("The password length must be selectable") { options.count == 1 && options.element.isHittable }
        let option = options.element
        if try !checked(option) {
            option.click()
            try driver.wait("The password length must update") { (try? self.checked(option)) == true }
            try assertEmptyResult()
        }
    }

    func generatePassword(length: Int, requiredSets: [String], excluded: String = "") throws -> String {
        try driver.wait("Generate must be enabled") { self.generate.isEnabled }
        generate.click()
        try driver.wait("A password of the selected length must be generated") {
            (self.result.value as? String)?.count == length && self.copy.isEnabled
        }
        guard let password = result.value as? String else { throw E2EError.condition("Cannot read the generated password") }
        let allowed = Set(requiredSets.joined())
        guard password.count == length,
              password.allSatisfy({ allowed.contains($0) && !excluded.contains($0) }),
              requiredSets.allSatisfy({ characters in password.contains { characters.contains($0) } }) else {
            throw E2EError.condition("The generated password does not satisfy the selected conditions")
        }
        return password
    }

    func copyPassword(_ password: String, clipboard: MacClipboard) throws {
        clipboard.expectCopy(of: password)
        copy.click()
        try driver.wait("Copy must report success and put the exact result on the clipboard") {
            self.driver.app.staticTexts["コピーしました。"].exists && clipboard.contains(password)
        }
    }

    func assertGenerationDisabled() throws {
        try driver.wait("No character types must disable generation") {
            !self.generate.isEnabled && self.driver.app.staticTexts["文字種を1つ以上選択してください。"].exists
        }
        try assertEmptyResult()
    }
}
