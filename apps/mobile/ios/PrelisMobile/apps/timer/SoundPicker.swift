import Foundation
import React
import UIKit
import UniformTypeIdentifiers

@MainActor
final class SoundPicker: NSObject, UIDocumentPickerDelegate {
  private let storage: SoundStorage
  private let queue: DispatchQueue
  private var picker: UIDocumentPickerViewController?
  private var resolve: RCTPromiseResolveBlock?
  private var reject: RCTPromiseRejectBlock?
  private var invalidated = false

  init(storage: SoundStorage, queue: DispatchQueue) { self.storage = storage; self.queue = queue }

  func pick(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard !invalidated else { reject("PICK_CANCELLED", "音声の選択を終了しました。", nil); return }
    guard self.resolve == nil else { reject("PICKER_BUSY", "音声の選択中です。", nil); return }
    guard let presenter = RCTPresentedViewController() else { reject("NO_ACTIVITY", "画面を開けませんでした。", nil); return }
    let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.mp3, .wav], asCopy: true)
    controller.delegate = self
    controller.allowsMultipleSelection = false
    picker = controller
    self.resolve = resolve
    self.reject = reject
    presenter.present(controller, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let completion = resolve
    clear()
    completion?(NSNull())
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let resolve = resolve, let reject = reject else { return }
    clear()
    let storage = storage
    let queue = queue
    queue.async { [weak self] in
      let result = Result { () throws -> [String: String] in
        guard let source = urls.first else { throw FileStorage.error("音声を開けませんでした。") }
        return try storage.importSound(source)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, !self.invalidated else {
          if case .success(let sound) = result, let id = sound["id"] {
            queue.async { try? storage.delete(id) }
          }
          reject("PICK_CANCELLED", "音声の選択を終了しました。", nil)
          return
        }
        switch result {
        case .success(let sound): resolve(sound)
        case .failure(let error): reject("PRELIS_ERROR", error.localizedDescription, error)
        }
      }
    }
  }

  private func clear() { picker = nil; resolve = nil; reject = nil }

  func invalidate() {
    invalidated = true
    reject?("PICK_CANCELLED", "音声の選択を終了しました。", nil)
    picker?.delegate = nil
    picker?.dismiss(animated: false)
    clear()
  }
}
