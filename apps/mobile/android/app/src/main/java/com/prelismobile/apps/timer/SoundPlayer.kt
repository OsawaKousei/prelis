package com.prelismobile.apps.timer

import android.media.MediaPlayer

internal class SoundPlayer(private val storage: SoundStorage) {
  private var player: MediaPlayer? = null
  fun play(id: String, loop: Boolean) {
    val file = storage.file(id)
    if (!file.exists()) throw IllegalStateException("音声が見つかりません。")
    stop()
    val next = MediaPlayer()
    try {
      next.setDataSource(file.absolutePath)
      next.isLooping = loop
      next.setOnCompletionListener { if (player === it) stop() }
      next.prepare()
      player = next
      next.start()
    } catch (error: Exception) { next.release(); player = null; throw error }
  }
  fun stop() { player?.release(); player = null }
}
