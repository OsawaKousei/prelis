package com.prelismobile.apps.diary

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule
import com.prelismobile.shared.resolvePromise
import com.prelismobile.specs.NativeDiarySpec

@ReactModule(name = DiaryModule.NAME)
class DiaryModule(context: ReactApplicationContext) : NativeDiarySpec(context) {
  private val storage = DiaryStorage(context)
  override fun readDiary(date: String, promise: Promise) = resolvePromise(promise) { storage.read(date) }
  override fun saveDiary(date: String, content: String, promise: Promise) = resolvePromise(promise) {
    storage.save(date, content)
    true
  }
  companion object { const val NAME = "NativeDiary" }
}
