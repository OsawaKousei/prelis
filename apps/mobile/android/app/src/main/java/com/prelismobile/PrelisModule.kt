package com.prelismobile

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableArray
import com.facebook.react.uimanager.ViewManager
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.util.UUID

class PrelisPackage : ReactPackage {
  override fun createNativeModules(context: ReactApplicationContext): List<NativeModule> = listOf(PrelisModule(context))
  override fun createViewManagers(context: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}

class PrelisModule(private val context: ReactApplicationContext) : ReactContextBaseJavaModule(context), ActivityEventListener {
  private val random = SecureRandom()
  private var pickerPromise: Promise? = null
  private var player: MediaPlayer? = null
  private val soundDir get() = File(context.filesDir, "timer/sounds")
  private val soundIndex get() = File(context.filesDir, "timer/sounds.json")
  private val datePattern = Regex("\\d{4}-\\d{2}-\\d{2}")
  private val idPattern = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

  init { context.addActivityEventListener(this) }
  override fun getName() = "PrelisNative"
  override fun onNewIntent(intent: Intent) = Unit

  private fun diaryFile(date: String): File {
    if (!datePattern.matches(date)) throw IllegalArgumentException("日付が正しくありません。")
    return File(context.filesDir, "diary/$date.txt")
  }

  @ReactMethod fun readDiary(date: String, promise: Promise) = resolve(promise) {
    val file = diaryFile(date)
    if (file.exists()) file.readText(Charsets.UTF_8) else ""
  }

  @ReactMethod fun saveDiary(date: String, content: String, promise: Promise) = resolve(promise) {
    val file = diaryFile(date)
    file.parentFile?.mkdirs()
    val temporary = File(file.parentFile, "${file.name}.tmp")
    temporary.writeText(content, Charsets.UTF_8)
    if (!temporary.renameTo(file)) throw IllegalStateException("日記を保存できませんでした。")
    true
  }

  @ReactMethod fun copyText(value: String, promise: Promise) = resolve(promise) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Prelis password", value))
    true
  }

  @ReactMethod fun randomBytes(count: Int, promise: Promise) = resolve(promise) {
    if (count !in 1..4096) throw IllegalArgumentException("乱数の長さが不正です。")
    val bytes = ByteArray(count)
    random.nextBytes(bytes)
    val result: WritableArray = Arguments.createArray()
    bytes.forEach { result.pushInt(it.toInt() and 255) }
    result
  }

  private fun emptyLibrary() = JSONObject().put("version", 1).put("sounds", JSONArray()).put("selectedId", JSONObject.NULL)
  private fun library(): JSONObject = if (soundIndex.exists()) JSONObject(soundIndex.readText(Charsets.UTF_8)) else emptyLibrary()
  private fun writeLibrary(value: JSONObject) {
    soundIndex.parentFile?.mkdirs()
    val temporary = File(soundIndex.parentFile, "sounds.json.tmp")
    temporary.writeText(value.toString(), Charsets.UTF_8)
    if (!temporary.renameTo(soundIndex)) throw IllegalStateException("音声一覧を保存できませんでした。")
  }
  private fun soundFile(id: String): File {
    if (!idPattern.matches(id)) throw IllegalArgumentException("音声IDが不正です。")
    return File(soundDir, id)
  }
  @ReactMethod fun loadSounds(promise: Promise) = resolve(promise) { library().toString() }

  @ReactMethod fun selectSound(id: String?, promise: Promise) = resolve(promise) {
    val data = library()
    if (id != null && !(0 until data.getJSONArray("sounds").length()).any { data.getJSONArray("sounds").getJSONObject(it).getString("id") == id })
      throw IllegalArgumentException("音声が見つかりません。")
    stopSoundInternal()
    data.put("selectedId", id ?: JSONObject.NULL)
    writeLibrary(data)
    data.toString()
  }

  @ReactMethod fun deleteSound(id: String, promise: Promise) = resolve(promise) {
    val data = library()
    val old = data.getJSONArray("sounds")
    val next = JSONArray()
    var found = false
    for (i in 0 until old.length()) {
      val sound = old.getJSONObject(i)
      if (sound.getString("id") == id) found = true else next.put(sound)
    }
    if (!found) throw IllegalArgumentException("音声が見つかりません。")
    data.put("sounds", next)
    if (data.optString("selectedId") == id) {
      stopSoundInternal()
      data.put("selectedId", JSONObject.NULL)
    }
    writeLibrary(data)
    soundFile(id).delete()
    data.toString()
  }

  @ReactMethod fun pickSound(promise: Promise) {
    if (pickerPromise != null) { promise.reject("PICKER_BUSY", "音声の選択中です。"); return }
    val activity = context.currentActivity ?: run { promise.reject("NO_ACTIVITY", "画面を開けませんでした。"); return }
    pickerPromise = promise
    try {
      val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "audio/*"
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/mpeg", "audio/wav", "audio/x-wav", "audio/wave"))
      }
      activity.startActivityForResult(intent, 4217)
    } catch (error: Exception) {
      pickerPromise = null
      promise.reject("PICK_FAILED", error)
    }
  }

  override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode != 4217) return
    val promise = pickerPromise ?: return
    pickerPromise = null
    if (resultCode != Activity.RESULT_OK || data?.data == null) { promise.resolve(null); return }
    resolve(promise) { importSound(data.data!!) }
  }

  private fun importSound(uri: Uri): String {
    var name = "sound"
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor: Cursor ->
      if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
    }
    val extension = name.substringAfterLast('.', "").lowercase()
    if (extension != "mp3" && extension != "wav") throw IllegalArgumentException("MP3 または WAV ファイルを選択してください。")
    val id = UUID.randomUUID().toString()
    val file = soundFile(id)
    soundDir.mkdirs()
    try {
      val input = context.contentResolver.openInputStream(uri) ?: throw IllegalStateException("音声を開けませんでした。")
      input.use { source ->
        file.outputStream().use { target ->
          val buffer = ByteArray(8192)
          var total = 0L
          while (true) {
            val read = source.read(buffer)
            if (read < 0) break
            total += read
            if (total > 10 * 1024 * 1024) throw IllegalArgumentException("音声ファイルは 10 MB 以下にしてください。")
            target.write(buffer, 0, read)
          }
          if (total == 0L) throw IllegalArgumentException("空の音声ファイルです。")
        }
      }
      val data = library()
      data.getJSONArray("sounds").put(JSONObject().put("id", id).put("name", name).put("mimeType", if (extension == "mp3") "audio/mpeg" else "audio/wav"))
      stopSoundInternal()
      data.put("selectedId", id)
      writeLibrary(data)
      return data.toString()
    } catch (error: Exception) {
      file.delete()
      throw error
    }
  }

  @ReactMethod fun playSound(id: String, loop: Boolean, promise: Promise) = resolve(promise) {
    val file = soundFile(id)
    if (!file.exists()) throw IllegalStateException("音声が見つかりません。")
    stopSoundInternal()
    val next = MediaPlayer()
    try {
      next.setDataSource(file.absolutePath)
      next.isLooping = loop
      next.setOnCompletionListener { stopSoundInternal() }
      next.prepare()
      player = next
      next.start()
    } catch (error: Exception) {
      next.release()
      player = null
      throw error
    }
    true
  }
  @ReactMethod fun stopSound(promise: Promise) = resolve(promise) { stopSoundInternal(); true }
  private fun stopSoundInternal() { player?.release(); player = null }
  override fun invalidate() { stopSoundInternal(); super.invalidate() }

  private fun resolve(promise: Promise, action: () -> Any?) {
    try { promise.resolve(action()) } catch (error: Exception) { promise.reject("PRELIS_ERROR", error) }
  }
}
