package com.example.multi_scanner_example

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.SystemClock
import android.util.Log

class MainActivity: FlutterFragmentActivity() {
    private var voiceHelper: VoiceCaptureHelper? = null
    private var glassesHelper: GlassesDisplayHelper? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceHelper = VoiceCaptureHelper(this)
        glassesHelper = GlassesDisplayHelper(this)
        voiceHelper?.onStateChange = {
            channel?.invokeMethod("voiceState", mapOf("capturing" to (voiceHelper?.isCapturing() ?: false)))
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flashlight_test")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVoice" -> {
                    voiceHelper?.startCapture()
                    result.success(if (voiceHelper?.isCapturing() == true) "capturing" else "starting")
                }
                "stopVoice" -> {
                    val res = voiceHelper?.stopCapture()
                    result.success(res)
                }
                "isCapturing" -> result.success(voiceHelper?.isCapturing() ?: false)
                "showGlassesDisplay" -> result.success(glassesHelper?.show() ?: false)
                "hideGlassesDisplay" -> {
                    glassesHelper?.hide()
                    result.success(true)
                }
                "isGlassesDisplayShowing" -> result.success(glassesHelper?.isShowing() ?: false)
                else -> result.notImplemented()
            }
        }
    }
}
