package com.prelismobile

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.prelismobile.apps.diary.DiaryModule
import com.prelismobile.apps.password.PasswordModule
import com.prelismobile.apps.timer.TimerSoundModule

class PrelisPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? = when (name) {
    DiaryModule.NAME -> DiaryModule(reactContext)
    TimerSoundModule.NAME -> TimerSoundModule(reactContext)
    PasswordModule.NAME -> PasswordModule(reactContext)
    else -> null
  }
  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    mapOf(
      DiaryModule.NAME to DiaryModule::class.java,
      TimerSoundModule.NAME to TimerSoundModule::class.java,
      PasswordModule.NAME to PasswordModule::class.java,
    ).mapValues { (name, type) -> ReactModuleInfo(name, type.name, false, false, false, true) }
  }
}
