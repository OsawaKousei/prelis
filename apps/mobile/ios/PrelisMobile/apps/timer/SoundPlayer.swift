import AVFoundation
import Foundation

// Owned and called on the main queue, including AVAudioPlayer delegate callbacks.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
  private let storage: SoundStorage
  private var player: AVAudioPlayer?

  init(storage: SoundStorage) { self.storage = storage }

  func play(_ id: String, loop: Bool) throws {
    let file = try storage.file(id)
    guard FileManager.default.fileExists(atPath: file.path) else { throw FileStorage.error("音声が見つかりません。") }
    stop()
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, options: [.mixWithOthers])
    try session.setActive(true)
    do {
      let next = try AVAudioPlayer(contentsOf: file)
      next.delegate = self
      next.numberOfLoops = loop ? -1 : 0
      guard next.play() else { throw FileStorage.error("音声を再生できませんでした。") }
      player = next
    } catch {
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      throw error
    }
  }

  func stop() {
    guard let current = player else { return }
    current.stop()
    current.delegate = nil
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if player === self.player { stop() }
  }
}
