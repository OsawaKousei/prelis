import Foundation
import React
import UIKit

@objc(PasswordService)
final class PasswordService: NSObject {
  @objc func copyText(_ value: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async {
      UIPasteboard.general.string = value
      resolve(true)
    }
  }

  @objc func randomBytes(_ count: Double, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard count.isFinite, count >= 1, count <= 4096, count.rounded(.towardZero) == count else {
      reject("PRELIS_ERROR", "乱数の長さが不正です。", nil)
      return
    }
    var bytes = [UInt8](repeating: 0, count: Int(count))
    bytes.withUnsafeMutableBytes { buffer in arc4random_buf(buffer.baseAddress!, buffer.count) }
    resolve(bytes.map { Int($0) })
  }
}
