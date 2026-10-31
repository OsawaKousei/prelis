package com.prelismobile.apps.timer

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.prelismobile.shared.storage.FileStorage
import java.io.File
import java.util.UUID

internal class SoundStorage(private val context: Context) {
  private val files = FileStorage(context)
  private val directory get() = File(files.root, "timer/sounds")
  private val index get() = File(files.root, "timer/sounds.json")
  fun readLibrary(): String? = files.readText(index)
  fun writeLibrary(content: String) = files.writeText(index, content)
  fun file(id: String): File {
    if (!Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(id))
      throw IllegalArgumentException("音声IDが不正です。")
    return File(directory, id)
  }
  fun delete(id: String) {
    val target = file(id)
    if (target.exists() && !target.delete()) throw IllegalStateException("音声を削除できませんでした。")
  }
  fun importSound(uri: Uri): WritableMap {
    var name = "sound"
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
      if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
    }
    val extension = name.substringAfterLast('.', "").lowercase()
    if (extension != "mp3" && extension != "wav") throw IllegalArgumentException("MP3 または WAV ファイルを選択してください。")
    val id = UUID.randomUUID().toString()
    val target = file(id)
    if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException("保存先を作成できませんでした。")
    try {
      val input = context.contentResolver.openInputStream(uri) ?: throw IllegalStateException("音声を開けませんでした。")
      input.use { source ->
        target.outputStream().use { output ->
          val buffer = ByteArray(8192)
          var total = 0L
          while (true) {
            val count = source.read(buffer)
            if (count < 0) break
            total += count
            if (total > 10 * 1024 * 1024) throw IllegalArgumentException("音声ファイルは 10 MB 以下にしてください。")
            output.write(buffer, 0, count)
          }
          if (total == 0L) throw IllegalArgumentException("空の音声ファイルです。")
        }
      }
      return Arguments.createMap().apply {
        putString("id", id); putString("name", name)
        putString("mimeType", if (extension == "mp3") "audio/mpeg" else "audio/wav")
      }
    } catch (error: Exception) { target.delete(); throw error }
  }
}
