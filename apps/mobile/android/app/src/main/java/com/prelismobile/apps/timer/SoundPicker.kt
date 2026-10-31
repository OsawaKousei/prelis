package com.prelismobile.apps.timer

import android.app.Activity
import android.content.Intent
import com.facebook.react.bridge.BaseActivityEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.prelismobile.shared.resolvePromise
import java.util.concurrent.Executor

internal class SoundPicker(
  private val context: ReactApplicationContext,
  private val storage: SoundStorage,
  private val executor: Executor,
) : BaseActivityEventListener() {
  private var pending: Promise? = null
  @Volatile private var closed = false
  init { context.addActivityEventListener(this) }
  fun pick(promise: Promise) {
    if (closed) { promise.reject("PICK_CANCELLED", "音声の選択を終了しました。"); return }
    if (pending != null) { promise.reject("PICKER_BUSY", "音声の選択中です。"); return }
    val activity = context.currentActivity ?: run { promise.reject("NO_ACTIVITY", "画面を開けませんでした。"); return }
    pending = promise
    try {
      val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "audio/*"
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/mpeg", "audio/wav", "audio/x-wav", "audio/wave"))
      }
      activity.startActivityForResult(intent, 4217)
    } catch (error: Exception) { pending = null; promise.reject("PICK_FAILED", error) }
  }
  override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode != 4217) return
    val promise = pending ?: return
    pending = null
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) { promise.resolve(null); return }
    executor.execute {
      resolvePromise(promise) {
        val sound = storage.importSound(uri)
        if (closed) {
          sound.getString("id")?.let { storage.delete(it) }
          throw IllegalStateException("音声の選択を終了しました。")
        }
        sound
      }
    }
  }
  fun invalidate() {
    closed = true
    context.removeActivityEventListener(this)
    pending?.reject("PICK_CANCELLED", "音声の選択を終了しました。")
    pending = null
  }
}
