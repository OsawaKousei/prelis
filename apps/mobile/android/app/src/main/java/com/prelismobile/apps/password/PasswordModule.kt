package com.prelismobile.apps.password

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.module.annotations.ReactModule
import com.prelismobile.shared.resolvePromise
import com.prelismobile.specs.NativePasswordSpec
import java.security.SecureRandom

@ReactModule(name = PasswordModule.NAME)
class PasswordModule(private val context: ReactApplicationContext) : NativePasswordSpec(context) {
  private val random = SecureRandom()
  override fun copyText(value: String, promise: Promise) {
    UiThreadUtil.runOnUiThread {
      resolvePromise(promise) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Prelis password", value))
        true
      }
    }
  }
  override fun randomBytes(count: Double, promise: Promise) = resolvePromise(promise) {
    if (!count.isFinite() || count < 1 || count > 4096 || count != count.toInt().toDouble())
      throw IllegalArgumentException("乱数の長さが不正です。")
    val bytes = ByteArray(count.toInt())
    random.nextBytes(bytes)
    Arguments.createArray().apply { bytes.forEach { pushInt(it.toInt() and 255) } }
  }
  companion object { const val NAME = "NativePassword" }
}
