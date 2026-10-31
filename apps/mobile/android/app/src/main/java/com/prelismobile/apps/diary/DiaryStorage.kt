package com.prelismobile.apps.diary

import android.content.Context
import com.prelismobile.shared.storage.FileStorage
import java.io.File

internal class DiaryStorage(context: Context) {
  private val files = FileStorage(context)
  private fun file(date: String): File {
    if (!Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(date)) throw IllegalArgumentException("日付が正しくありません。")
    return File(files.root, "diary/$date.txt")
  }
  fun read(date: String): String = files.readText(file(date)) ?: ""
  fun save(date: String, content: String) = files.writeText(file(date), content)
}
