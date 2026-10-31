import Foundation
import React

@objc(DiaryService)
final class DiaryService: NSObject {
  private let storage = DiaryStorage()
  private let queue = DispatchQueue(label: "jp.co.kupacllc.prelis.diary")

  @objc func readDiary(_ date: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    queue.async {
      do { resolve(try self.storage.read(date)) }
      catch { reject("PRELIS_ERROR", error.localizedDescription, error) }
    }
  }

  @objc func saveDiary(_ date: String, content: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    queue.async {
      do { try self.storage.save(date, content: content); resolve(true) }
      catch { reject("PRELIS_ERROR", error.localizedDescription, error) }
    }
  }
}
