import Foundation

enum FileStorage {
  static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  }

  static func error(_ message: String) -> NSError {
    NSError(domain: "PrelisNative", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  static func ensureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  static func readText(_ url: URL) throws -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func writeText(_ content: String, to url: URL) throws {
    try ensureDirectory(url.deletingLastPathComponent())
    try content.write(to: url, atomically: true, encoding: .utf8)
  }
}
