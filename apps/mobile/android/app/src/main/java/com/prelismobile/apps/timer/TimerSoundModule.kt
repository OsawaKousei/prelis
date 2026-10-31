package com.prelismobile.apps.timer

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.module.annotations.ReactModule
import com.prelismobile.shared.resolvePromise
import com.prelismobile.specs.NativeTimerSoundSpec
import java.util.concurrent.Executors

@ReactModule(name = TimerSoundModule.NAME)
class TimerSoundModule(context: ReactApplicationContext) : NativeTimerSoundSpec(context) {
  private val storage = SoundStorage(context)
  private val executor = Executors.newSingleThreadExecutor()
  private val picker = SoundPicker(context, storage, executor)
  private val player = SoundPlayer(storage)
  override fun readLibrary(promise: Promise) {
    executor.execute { resolvePromise(promise) { storage.readLibrary() } }
  }
  override fun writeLibrary(content: String, promise: Promise) {
    executor.execute { resolvePromise(promise) { storage.writeLibrary(content); true } }
  }
  override fun deleteSoundFile(id: String, promise: Promise) {
    executor.execute { resolvePromise(promise) { storage.delete(id); true } }
  }
  override fun pickSound(promise: Promise) { UiThreadUtil.runOnUiThread { picker.pick(promise) } }
  override fun playSound(id: String, loop: Boolean, promise: Promise) {
    UiThreadUtil.runOnUiThread { resolvePromise(promise) { player.play(id, loop); true } }
  }
  override fun stopSound(promise: Promise) {
    UiThreadUtil.runOnUiThread { resolvePromise(promise) { player.stop(); true } }
  }
  override fun invalidate() {
    UiThreadUtil.runOnUiThread { picker.invalidate(); player.stop(); executor.shutdown() }
    super.invalidate()
  }
  companion object { const val NAME = "NativeTimerSound" }
}
