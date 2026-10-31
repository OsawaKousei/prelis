import SwiftUI

@main
struct NativeSmokeFixture: App {
  init() {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    do {
      try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
      let source = Bundle.main.url(forResource: "swift-native-smoke", withExtension: "wav")!
      try Data(contentsOf: source).write(to: documents.appendingPathComponent("swift-native-smoke.wav"))
      try Data().write(to: documents.appendingPathComponent("swift-native-empty.wav"))
    } catch { fatalError("Cannot prepare smoke fixtures: \(error)") }
  }

  var body: some Scene { WindowGroup { Text("Native smoke fixtures ready") } }
}
