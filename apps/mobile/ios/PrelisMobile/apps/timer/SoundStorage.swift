import Foundation

final class SoundStorage: Sendable {
  private let maximumBytes = 10 * 1024 * 1024
  private var directory: URL { FileStorage.root.appendingPathComponent("timer/sounds", isDirectory: true) }
  private var index: URL { FileStorage.root.appendingPathComponent("timer/sounds.json") }

  func readLibrary() throws -> String? { try FileStorage.readText(index) }
  func writeLibrary(_ content: String) throws { try FileStorage.writeText(content, to: index) }

  func file(_ id: String) throws -> URL {
    guard id.count == 36, id.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil else {
      throw FileStorage.error("音声IDが不正です。")
    }
    return directory.appendingPathComponent(id)
  }

  func delete(_ id: String) throws {
    let url = try file(id)
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
  }

  func importSound(_ source: URL) throws -> [String: String] {
    let name = source.lastPathComponent
    let ext = source.pathExtension.lowercased()
    guard ext == "mp3" || ext == "wav" else { throw FileStorage.error("MP3 または WAV ファイルを選択してください。") }
    let id = UUID().uuidString.lowercased()
    let target = try file(id)
    try FileStorage.ensureDirectory(directory)
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    guard let input = InputStream(url: source), let output = OutputStream(url: target, append: false) else {
      throw FileStorage.error("音声を開けませんでした。")
    }
    input.open()
    output.open()
    defer { input.close(); output.close() }
    do {
      var buffer = [UInt8](repeating: 0, count: 8192)
      var total = 0
      while true {
        let count = input.read(&buffer, maxLength: 8192)
        if count == 0 { break }
        if count < 0 { throw input.streamError ?? FileStorage.error("音声を読み込めませんでした。") }
        total += count
        guard total <= maximumBytes else { throw FileStorage.error("音声ファイルは 10 MB 以下にしてください。") }
        try buffer.withUnsafeBufferPointer { bytes in
          var offset = 0
          while offset < count {
            let written = output.write(bytes.baseAddress!.advanced(by: offset), maxLength: count - offset)
            guard written > 0 else { throw output.streamError ?? FileStorage.error("音声を保存できませんでした。") }
            offset += written
          }
        }
      }
      guard total > 0 else { throw FileStorage.error("空の音声ファイルです。") }
    } catch {
      input.close()
      output.close()
      try? FileManager.default.removeItem(at: target)
      throw error
    }
    return ["id": id, "name": name, "mimeType": ext == "mp3" ? "audio/mpeg" : "audio/wav"]
  }
}
