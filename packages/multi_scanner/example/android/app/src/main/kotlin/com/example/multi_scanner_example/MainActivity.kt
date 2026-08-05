package com.example.multi_scanner_example

import ru.tander.smart_glasses.BuildConfig
import android.app.Application
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.content.pm.PackageManager
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var engineGroup: FlutterEngineGroup? = null
    private var glassesEngine: FlutterEngine? = null
    private var voiceHelper: VoiceCaptureHelper? = null
    private var glassesHelper: GlassesDisplayHelper? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineGroup = FlutterEngineGroup(this)
        voiceHelper = VoiceCaptureHelper(this)
        voiceHelper?.onStateChange = {
            channel?.invokeMethod(
                "voiceState",
                mapOf("capturing" to (voiceHelper?.isCapturing() ?: false)),
            )
        }
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flashlight_test",
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVoice" -> {
                    val helper = voiceHelper
                    if (helper == null) {
                        result.error("VOICE_UNAVAILABLE", "Voice helper is unavailable", null)
                    } else {
                        helper.startCapture { outcome ->
                            outcome.fold(
                                onSuccess = result::success,
                                onFailure = { error ->
                                    result.error(
                                        "VOICE_START_FAILED",
                                        error.message ?: error.toString(),
                                        null,
                                    )
                                },
                            )
                        }
                    }
                }

                "stopVoice" -> {
                    val helper = voiceHelper
                    if (helper == null) {
                        result.success("already stopped")
                    } else {
                        helper.stopCapture { outcome ->
                            outcome.fold(
                                onSuccess = result::success,
                                onFailure = { error ->
                                    result.error(
                                        "VOICE_STOP_FAILED",
                                        error.message ?: error.toString(),
                                        null,
                                    )
                                },
                            )
                        }
                    }
                }

                "isCapturing" -> result.success(voiceHelper?.isCapturing() ?: false)
                "showGlassesDisplay" -> result.success(showGlassesDisplay())
                "hideGlassesDisplay" -> {
                    glassesHelper?.hide()
                    result.success(true)
                }

                "isGlassesDisplayShowing" ->
                    result.success(glassesHelper?.isShowing() ?: false)

                "getParityNativeDiagnostics" -> result.success(nativeDiagnostics())
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(
            TAG,
            "created package=$packageName uid=${Process.myUid()} " +
                "identityParity=${BuildConfig.MAIN_APP_IDENTITY_PARITY} " +
                "manufacturer=${Build.MANUFACTURER} model=${Build.MODEL}",
        )
    }

    private fun ensureGlassesEngine(): FlutterEngine? {
        glassesEngine?.let { return it }
        val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        val entrypoint = DartExecutor.DartEntrypoint(bundlePath, "glassesMain")
        val engine = engineGroup?.createAndRunEngine(this, entrypoint) ?: return null
        glassesEngine = engine
        Log.i(TAG, "secondary Flutter engine started")
        return engine
    }

    private fun showGlassesDisplay(): Boolean {
        val engine = ensureGlassesEngine() ?: return false
        val helper = glassesHelper ?: GlassesDisplayHelper(this, engine).also {
            glassesHelper = it
        }
        return helper.show()
    }

    private fun nativeDiagnostics(): Map<String, Any?> {
        val requestedPermissions = runCatching {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_PERMISSIONS,
            ).requestedPermissions
                ?.toList()
                .orEmpty()
        }.getOrDefault(emptyList())
        return mapOf(
            "applicationId" to BuildConfig.APPLICATION_ID,
            "packageName" to packageName,
            "namespace" to "ru.tander.smart_glasses",
            "identityParity" to BuildConfig.MAIN_APP_IDENTITY_PARITY,
            "uid" to Process.myUid(),
            "process" to if (Build.VERSION.SDK_INT >= 28) {
                Application.getProcessName()
            } else {
                packageName
            },
            "primaryFlutterEngine" to true,
            "secondaryFlutterEngine" to (glassesEngine != null),
            "flutterEngineCount" to if (glassesEngine == null) 1 else 2,
            "glassesDisplayShowing" to (glassesHelper?.isShowing() ?: false),
            "voice" to (voiceHelper?.diagnostics() ?: emptyMap<String, Any>()),
            "requestedPermissions" to requestedPermissions,
        )
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        voiceHelper?.close()
        voiceHelper = null
        glassesHelper?.hide()
        glassesHelper = null
        glassesEngine?.destroy()
        glassesEngine = null
        engineGroup = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MainAppParity"
    }
}
