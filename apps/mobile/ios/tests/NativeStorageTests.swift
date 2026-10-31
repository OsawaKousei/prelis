import XCTest

final class NativeStorageTests: XCTestCase {
  func testDiaryPreservesUTF8AndRejectsUnsafeDates() throws {
    let storage = DiaryStorage()
    let date = "0001-01-01"
    let file = FileStorage.root.appendingPathComponent("diary/\(date).txt")
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertEqual(try storage.read(date), "")
    try storage.save(date, content: "Swift移行の確認\n日記を保存する。🙂")
    XCTAssertEqual(try storage.read(date), "Swift移行の確認\n日記を保存する。🙂")
    try storage.save(date, content: "")
    XCTAssertEqual(try storage.read(date), "")
    XCTAssertThrowsError(try storage.save("../../outside", content: "invalid"))
  }

  func testSoundImportPreservesBytesAndCleansRejectedFiles() throws {
    let storage = SoundStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileStorage.ensureDirectory(directory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("sample.WAV")
    let bytes = Data(repeating: 7, count: 8193)
    try bytes.write(to: source)
    let sound = try storage.importSound(source)
    let id = try XCTUnwrap(sound["id"])
    defer { try? storage.delete(id) }
    XCTAssertEqual(sound["mimeType"], "audio/wav")
    XCTAssertEqual(try Data(contentsOf: storage.file(id)), bytes)
    XCTAssertThrowsError(try storage.file("../outside"))

    let sounds = FileStorage.root.appendingPathComponent("timer/sounds")
    let before = Set(try FileManager.default.contentsOfDirectory(atPath: sounds.path))
    let empty = directory.appendingPathComponent("empty.wav")
    try Data().write(to: empty)
    XCTAssertThrowsError(try storage.importSound(empty))
    let large = directory.appendingPathComponent("large.wav")
    try Data(repeating: 0, count: 10 * 1024 * 1024 + 1).write(to: large)
    XCTAssertThrowsError(try storage.importSound(large))
    let invalid = directory.appendingPathComponent("invalid.txt")
    try bytes.write(to: invalid)
    XCTAssertThrowsError(try storage.importSound(invalid))
    XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: sounds.path)), before)
    try storage.delete(id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: try storage.file(id).path))
  }
}
