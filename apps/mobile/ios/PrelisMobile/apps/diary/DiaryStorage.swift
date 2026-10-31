import Foundation

final class DiaryStorage {
  private func file(_ date: String) throws -> URL {
    guard date.count == 10, date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
      throw FileStorage.error("日付が正しくありません。")
    }
    return FileStorage.root.appendingPathComponent("diary", isDirectory: true).appendingPathComponent("\(date).txt")
  }

  func read(_ date: String) throws -> String { try FileStorage.readText(file(date)) ?? "" }
  func save(_ date: String, content: String) throws { try FileStorage.writeText(content, to: file(date)) }
}
