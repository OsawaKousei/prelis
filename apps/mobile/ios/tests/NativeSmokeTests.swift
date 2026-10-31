import XCTest

final class NativeSmokeTests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "jp.co.kupac.prelis")

  override func setUpWithError() throws { continueAfterFailure = false }

  private func tap(_ label: String) {
    for _ in 0..<6 {
      let matches = app.buttons.matching(NSPredicate(
        format: "label == %@ OR label BEGINSWITH %@", label, label + ", tab,"
      )).allElementsBoundByIndex
      if let button = matches.first(where: { $0.isHittable }) { button.tap(); return }
      guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: {
        $0.frame.height > 300 && $0.frame.minY < 200
      }) else { XCTFail("Main scroll view is missing"); return }
      let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.40))
      let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.05))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
    XCTFail("Control is not hittable: \(label)\n\(app.debugDescription)")
  }

  private func chooseFile(_ name: String) {
    // Files may hide extensions and append type, date and size to the cell label.
    let stem = (name as NSString).deletingPathExtension
    let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", stem + ",", name + ",")).firstMatch
    if !file.waitForExistence(timeout: 3) {
      let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "ブラウズ"])).firstMatch
      if browse.exists && browse.isHittable { browse.tap() }
      let location = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "このiPhone内"])).firstMatch
      XCTAssertTrue(location.waitForExistence(timeout: 10), app.debugDescription)
      location.tap()
      let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Native Smoke Fixtures")).firstMatch
      XCTAssertTrue(folder.waitForExistence(timeout: 10), app.debugDescription)
      folder.tap()
    }
    XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
    file.tap()
  }

  func testExpoFeaturesThroughUI() throws {
    let fixture = XCUIApplication(bundleIdentifier: "jp.co.kupac.prelis.native-smoke-fixture")
    fixture.launch()
    XCTAssertTrue(fixture.staticTexts["Native smoke fixtures ready"].waitForExistence(timeout: 10))
    app.launch()
    XCTAssertTrue(app.staticTexts["アプリを選択"].waitForExistence(timeout: 20), app.debugDescription)
    tap("Diary")
    let editor = app.textViews["日記の本文"]
    XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
    editor.tap()
    editor.typeText("swift-native-smoke")
    tap("保存")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["アプリを選択"].waitForExistence(timeout: 20))
    tap("Diary")
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    XCTAssertEqual(editor.value as? String, "swift-native-smoke")

    tap("Password")
    tap("パスワードを生成")
    let password = app.textFields["生成したパスワード"]
    XCTAssertTrue(password.waitForExistence(timeout: 10), app.debugDescription)
    let value = try XCTUnwrap(password.value as? String)
    XCTAssertEqual(value.count, 16)
    for pattern in ["[A-Z]", "[a-z]", "[0-9]", "[!@#$%^&*_=+?-]"] {
      XCTAssertNotNil(value.range(of: pattern, options: .regularExpression))
    }
    tap("コピー")
    XCTAssertTrue(app.staticTexts["コピーしました。"].waitForExistence(timeout: 5))

    tap("Timer")
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["開始"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    tap("音声設定を開く")
    tap("音声を追加（MP3 / WAV、10 MB 以下）")
    let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "キャンセル"])).firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
    cancel.tap()
    tap("音声を追加（MP3 / WAV、10 MB 以下）")
    chooseFile("swift-native-empty.wav")
    XCTAssertTrue(app.staticTexts["空の音声ファイルです。"].waitForExistence(timeout: 10), app.debugDescription)
    tap("音声を追加（MP3 / WAV、10 MB 以下）")
    chooseFile("swift-native-smoke.wav")
    XCTAssertTrue(app.buttons["swift-native-smoke.wav"].waitForExistence(timeout: 10), app.debugDescription)
    tap("試聴")
    XCTAssertFalse(app.staticTexts["音声を再生できませんでした。"].exists)

    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["アプリを選択"].waitForExistence(timeout: 20))
    tap("Timer")
    XCTAssertTrue(app.staticTexts["選択中: swift-native-smoke.wav"].waitForExistence(timeout: 10))
    let minutes = app.textFields["時間（分）"]
    minutes.tap()
    minutes.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "1\n")
    tap("開始")
    tap("Diary")
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    tap("Timer")
    let clock = app.descendants(matching: .any).matching(identifier: "timer-clock").firstMatch
    let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "00:00"), object: clock)
    XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 75), .completed)
    XCTAssertFalse(app.staticTexts["終了音を再生できませんでした。"].exists)
    tap("リセット")
    tap("音声設定を開く")
    tap("選択中の音声を削除")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["アプリを選択"].waitForExistence(timeout: 20))
    tap("Timer")
    XCTAssertTrue(app.staticTexts["選択中: なし"].waitForExistence(timeout: 10))
  }
}
