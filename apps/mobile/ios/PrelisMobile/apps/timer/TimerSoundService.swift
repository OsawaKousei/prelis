import Foundation
import React

@objc(TimerSoundService)
final class TimerSoundService: NSObject {
  private let storage = SoundStorage()
  private let queue = DispatchQueue(label: "jp.co.kupacllc.prelis.timer")
  // These properties are accessed only from DispatchQueue.main.
  private var picker: SoundPicker?
  private var player: SoundPlayer?
  private var invalidated = false

  @objc func readLibrary(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    queue.async {
      do {
        // React Native converts a nil promise result to undefined, not null.
        if let content = try self.storage.readLibrary() { resolve(content) }
        else { resolve(NSNull()) }
      }
      catch { reject("PRELIS_ERROR", error.localizedDescription, error) }
    }
  }

  @objc func writeLibrary(_ content: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    queue.async {
      do { try self.storage.writeLibrary(content); resolve(true) }
      catch { reject("PRELIS_ERROR", error.localizedDescription, error) }
    }
  }

  @objc func deleteSoundFile(_ id: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    queue.async {
      do { try self.storage.delete(id); resolve(true) }
      catch { reject("PRELIS_ERROR", error.localizedDescription, error) }
    }
  }

  @objc func pickSound(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async {
      guard !self.invalidated else { reject("PICK_CANCELLED", "音声の選択を終了しました。", nil); return }
      if self.picker == nil { self.picker = SoundPicker(storage: self.storage, queue: self.queue) }
      self.picker?.pick(resolve: resolve, reject: reject)
    }
  }

  @objc func playSound(_ id: String, loop: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async {
      guard !self.invalidated else { reject("PRELIS_ERROR", "音声の再生を終了しました。", nil); return }
      if self.player == nil { self.player = SoundPlayer(storage: self.storage) }
      do { try self.player?.play(id, loop: loop); resolve(true) }
      catch { reject("PRELIS_ERROR", error.localizedDescription, error) }
    }
  }

  @objc func stopSound(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async { self.player?.stop(); resolve(true) }
  }

  @objc func invalidate() {
    DispatchQueue.main.async {
      self.invalidated = true
      self.picker?.invalidate()
      self.picker = nil
      self.player?.stop()
      self.player = nil
    }
  }
}
