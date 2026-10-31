package com.prelismobile.shared.storage

import android.content.Context
import java.io.File

internal class FileStorage(context: Context) {
  val root: File = context.filesDir

  fun readText(file: File): String? = if (file.exists()) file.readText(Charsets.UTF_8) else null

  fun writeText(file: File, content: String) {
    val directory = file.parentFile ?: throw IllegalArgumentException("保存先が不正です。")
    if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException("保存先を作成できませんでした。")
    val temporary = File.createTempFile(file.name, ".tmp", directory)
    try {
      temporary.writeText(content, Charsets.UTF_8)
      if (!temporary.renameTo(file)) throw IllegalStateException("ファイルを保存できませんでした。")
    } finally { temporary.delete() }
  }
}
