package com.prelismobile.shared

import com.facebook.react.bridge.Promise

internal fun resolvePromise(promise: Promise, action: () -> Any?) {
  try { promise.resolve(action()) } catch (error: Exception) { promise.reject("PRELIS_ERROR", error) }
}
