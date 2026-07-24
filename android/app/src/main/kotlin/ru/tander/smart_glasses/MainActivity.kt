package ru.tander.smart_glasses

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.Point
import android.net.Uri
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterView
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val WEAR_OPERATION_TIMEOUT_MS = 5_000L
    }

    private var engineGroup: FlutterEngineGroup? = null
    private var glassesEngine: FlutterEngine? = null
    private var glassesChannel: MethodChannel? = null
    private var appChannel: MethodChannel? = null
    private var glassesPresentation: GlassesPresentation? = null
    private var displayManager: DisplayManager? = null
    private var currentCounter = 0
    private var currentRecognizedText = ""
    private var currentWearGlassesPayload: Map<*, *>? = null
    private var wearProjectionGeneration = 0
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingWearResults = mutableSetOf<BoundedResult>()
    private var pendingWearShowResult: BoundedResult? = null
    private var audioManager: AudioManager? = null
    private var audioRecordingCallback: AudioManager.AudioRecordingCallback? = null
    private var lastAudioCaptureSilenced: Boolean? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        engineGroup = FlutterEngineGroup(this)

        // Pre-warm secondary engine in advance
        val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        val dartEntrypoint = DartExecutor.DartEntrypoint(bundlePath, "glassesMain")
        glassesEngine = engineGroup?.createAndRunEngine(this, dartEntrypoint)
        if (glassesEngine != null) {
            glassesChannel = MethodChannel(glassesEngine!!.dartExecutor.binaryMessenger, "glasses_channel")
            glassesChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialCounter" -> {
                        Log.d("SmartWear", "Glasses requested initial counter: $currentCounter")
                        result.success(currentCounter)
                    }
                    else -> result.notImplemented()
                }
            }
            Log.d("SmartWear", "Secondary engine pre-warmed")
        }

        appChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app_channel")
        appChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "showGlassesInitialization" -> {
                        Log.d("SmartWear", "showGlassesInitialization called")
                        showGlassesInitialization()
                        result.success(true)
                    }
                    "navigateGlassesToEmpty" -> {
                        Log.d("SmartWear", "navigateGlassesToEmpty called")
                        navigateGlassesToEmpty()
                        result.success(true)
                    }
                    "updateCounter" -> {
                        currentCounter = call.arguments as Int
                        Log.d("SmartWear", "updateCounter received: $currentCounter")
                        updateGlassesCounter(currentCounter)
                        result.success(true)
                    }
                    "updateRecognizedText" -> {
                        currentRecognizedText = call.arguments as? String ?: ""
                        updateGlassesRecognizedText(currentRecognizedText)
                        result.success(true)
                    }
                    "showWearGlasses" -> {
                        val payload = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                        Log.d("SmartWear", "showWearGlasses called: $payload")
                        showWearGlasses(payload, result)
                    }
                    "updateWearGlasses" -> {
                        val payload = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                        Log.d("SmartWear", "updateWearGlasses called: $payload")
                        updateWearGlasses(payload, result)
                    }
                    "updateWearVoiceOverlay" -> {
                        val payload = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                        Log.d("SmartWear", "updateWearVoiceOverlay called: $payload")
                        updateWearVoiceOverlay(payload, result)
                    }
                    "hideWearGlasses" -> {
                        Log.d("SmartWear", "hideWearGlasses called")
                        hideWearGlasses(result)
                    }
                    "copyPhotoToAppStorage" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("INVALID_PHOTO_URI", "Photo URI is required", null)
                        } else {
                            copyPhotoToAppStorage(uri, result)
                        }
                    }
                    "saveLogs" -> {
                        saveLogsToFile()
                        result.success(true)
                    }
                    "clearLogs" -> {
                        clearLogs()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        registerAudioRecordingMonitor()
    }

    private fun registerAudioRecordingMonitor() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.d("VoiceCapture", "silence monitoring unavailable below Android 10")
            return
        }
        val manager = getSystemService(AudioManager::class.java)
        val callback = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: List<android.media.AudioRecordingConfiguration>) {
                val ownRecordings = configs.filter {
                    it.clientAudioSource == MediaRecorder.AudioSource.VOICE_COMMUNICATION
                }
                if (ownRecordings.isEmpty()) {
                    Log.d("VoiceCapture", "VOICE_COMMUNICATION recording config removed")
                    if (lastAudioCaptureSilenced == true) {
                        appChannel?.invokeMethod("audioCaptureSilencedChanged", false)
                    }
                    lastAudioCaptureSilenced = null
                    return
                }

                val silenced = ownRecordings.any { it.isClientSilenced }
                Log.d(
                    "VoiceCapture",
                    "recording configs=" + ownRecordings.joinToString { config ->
                        "session=${config.clientAudioSessionId}, " +
                            "source=${config.clientAudioSource}, " +
                            "silenced=${config.isClientSilenced}"
                    },
                )
                if (silenced == lastAudioCaptureSilenced) return
                lastAudioCaptureSilenced = silenced
                appChannel?.invokeMethod("audioCaptureSilencedChanged", silenced)
            }
        }
        audioManager = manager
        audioRecordingCallback = callback
        manager.registerAudioRecordingCallback(callback, mainHandler)
    }

    private fun copyPhotoToAppStorage(uri: String, result: MethodChannel.Result) {
        Thread {
            try {
                val photoDirectory = java.io.File(filesDir, "wear_photos")
                if (!photoDirectory.exists() && !photoDirectory.mkdirs()) {
                    throw IllegalStateException("Unable to create photo directory")
                }
                val destination = java.io.File(photoDirectory, "latest_photo")
                val temporary = java.io.File(photoDirectory, "latest_photo.tmp")
                contentResolver.openInputStream(Uri.parse(uri)).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Unable to open photo URI")
                    }
                    temporary.outputStream().use { output -> input.copyTo(output) }
                }
                if (destination.exists() && !destination.delete()) {
                    throw IllegalStateException("Unable to replace previous photo")
                }
                if (!temporary.renameTo(destination)) {
                    throw IllegalStateException("Unable to save photo")
                }
                mainHandler.post { result.success(destination.absolutePath) }
            } catch (error: Exception) {
                Log.e("SmartWear", "Failed to copy photo", error)
                mainHandler.post {
                    result.error(
                        "PHOTO_COPY_FAILED",
                        error.message ?: "Failed to copy photo",
                        null
                    )
                }
            }
        }.start()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        displayManager = getSystemService(DISPLAY_SERVICE) as DisplayManager

        // Логируем информацию о всех подключенных дисплеях
        logConnectedDisplays(this)
    }

    private fun showGlassesInitialization() {
        Log.d("SmartWear", "showGlassesInitialization() called")
        invalidatePendingWearShow()
        val displays = displayManager?.getDisplays()
        if (displays != null && displays.size > 1) {
            val secondaryDisplay = displays[displays.size - 1]

            glassesPresentation?.dismiss()
            currentWearGlassesPayload = null

            if (glassesEngine != null) {
                glassesPresentation = GlassesPresentation(this, secondaryDisplay, glassesEngine!!)
                glassesPresentation?.show()
                Log.d("SmartWear", "Glasses presentation shown, navigating to initialization")
                glassesChannel?.invokeMethod("navigateToRoute", "/initialization")
            }
        } else {
            Log.d("SmartWear", "No secondary display found")
        }
    }

    private fun navigateGlassesToEmpty() {
        Log.d("SmartWear", "navigateGlassesToEmpty() called")
        invalidatePendingWearShow()
        glassesChannel?.invokeMethod("navigateToRoute", "/empty")
    }

    private fun showWearGlasses(payload: Map<*, *>, result: MethodChannel.Result) {
        invalidatePendingWearShow()
        val generation = wearProjectionGeneration
        currentWearGlassesPayload = payload
        val displays = displayManager?.getDisplays()
        if (displays != null && displays.size > 1) {
            val secondaryDisplay = displays[displays.size - 1]

            val engine = glassesEngine
            val channel = glassesChannel
            if (engine == null || channel == null) {
                result.error("GLASSES_ENGINE_UNAVAILABLE", "Secondary Flutter engine is unavailable", null)
                return
            }
            if (glassesPresentation == null) {
                glassesPresentation = GlassesPresentation(this, secondaryDisplay, engine)
                glassesPresentation?.show()
            }

            Log.d("SmartWear", "Navigating to wear projection on glasses")
            val pendingResult = BoundedResult(
                result,
                "showWearGlasses",
                onTimeout = {
                    if (generation == wearProjectionGeneration) {
                        wearProjectionGeneration++
                        channel.invokeMethod("navigateToRoute", "/empty")
                    }
                }
            )
            pendingWearShowResult = pendingResult
            channel.invokeMethod("updateWearGlasses", payload, object : MethodChannel.Result {
                override fun success(updateResult: Any?) {
                    if (generation != wearProjectionGeneration) {
                        pendingResult.error(
                            "GLASSES_OPERATION_SUPERSEDED",
                            "Wear projection show was superseded",
                            null
                        )
                        return
                    }
                    if (!pendingResult.isPending()) {
                        return
                    }
                    channel.invokeMethod(
                        "navigateToRoute",
                        "/wear",
                        pendingResult
                    )
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    pendingResult.error(errorCode, errorMessage, errorDetails)
                }

                override fun notImplemented() {
                    pendingResult.notImplemented()
                }
            })
        } else {
            Log.d("SmartWear", "No secondary display found for wear projection")
            result.error("GLASSES_DISPLAY_UNAVAILABLE", "No secondary display found", null)
        }
    }

    private fun updateWearGlasses(payload: Map<*, *>, result: MethodChannel.Result) {
        currentWearGlassesPayload = payload
        if (glassesPresentation == null) {
            Log.d("SmartWear", "Wear projection update requested before presentation; creating presentation")
            showWearGlasses(payload, result)
            return
        }
        val channel = glassesChannel
        if (channel == null) {
            result.error("GLASSES_ENGINE_UNAVAILABLE", "Secondary Flutter channel is unavailable", null)
            return
        }
        channel.invokeMethod(
            "updateWearGlasses",
            payload,
            BoundedResult(result, "updateWearGlasses")
        )
    }

    private fun updateWearVoiceOverlay(payload: Map<*, *>, result: MethodChannel.Result) {
        val channel = glassesChannel
        if (channel == null) {
            result.error("GLASSES_ENGINE_UNAVAILABLE", "Secondary Flutter channel is unavailable", null)
            return
        }
        channel.invokeMethod(
            "updateWearVoiceOverlay",
            payload,
            BoundedResult(result, "updateWearVoiceOverlay")
        )
    }

    private fun hideWearGlasses(result: MethodChannel.Result) {
        invalidatePendingWearShow()
        currentWearGlassesPayload = null
        val channel = glassesChannel
        if (channel == null) {
            result.error("GLASSES_ENGINE_UNAVAILABLE", "Secondary Flutter channel is unavailable", null)
            return
        }
        channel.invokeMethod(
            "navigateToRoute",
            "/empty",
            BoundedResult(result, "navigateToRoute")
        )
    }

    private fun invalidatePendingWearShow() {
        wearProjectionGeneration++
        pendingWearShowResult?.error(
            "GLASSES_OPERATION_SUPERSEDED",
            "Wear projection show was superseded",
            null
        )
        pendingWearShowResult = null
    }

    private fun supersedePendingWearResults() {
        val pendingResults = synchronized(pendingWearResults) {
            pendingWearResults.toList()
        }
        pendingResults.forEach {
            it.error(
                "GLASSES_OPERATION_SUPERSEDED",
                "Wear projection operation was superseded",
                null
            )
        }
    }

    private inner class BoundedResult(
        private val target: MethodChannel.Result,
        private val operation: String,
        private val onTimeout: (() -> Unit)? = null
    ) : MethodChannel.Result {
        private val completed = AtomicBoolean(false)
        private val timeout = Runnable {
            onTimeout?.invoke()
            error(
                "GLASSES_OPERATION_TIMEOUT",
                "Timed out waiting for $operation acknowledgement",
                null
            )
        }

        init {
            synchronized(pendingWearResults) {
                pendingWearResults.add(this)
            }
            mainHandler.postDelayed(timeout, WEAR_OPERATION_TIMEOUT_MS)
        }

        fun isPending(): Boolean = !completed.get()

        override fun success(result: Any?) {
            complete { target.success(result) }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            complete {
                Log.e("SmartWear", "forward $operation error $errorCode: $errorMessage")
                target.error(errorCode, errorMessage, errorDetails)
            }
        }

        override fun notImplemented() {
            complete {
                Log.e("SmartWear", "forward $operation notImplemented")
                target.notImplemented()
            }
        }

        private fun complete(completion: () -> Unit) {
            if (!completed.compareAndSet(false, true)) {
                return
            }
            mainHandler.removeCallbacks(timeout)
            synchronized(pendingWearResults) {
                pendingWearResults.remove(this)
            }
            completion()
        }
    }

    private fun updateGlassesCounter(counter: Int) {
        Log.d("SmartWear", "updateGlassesCounter() sending: $counter")
        glassesChannel?.invokeMethod("updateCounter", counter)
    }

    private fun updateGlassesRecognizedText(text: String) {
        glassesChannel?.invokeMethod("updateRecognizedText", text)
    }

    override fun onDestroy() {
        invalidatePendingWearShow()
        supersedePendingWearResults()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            audioRecordingCallback?.let { callback ->
                audioManager?.unregisterAudioRecordingCallback(callback)
            }
        }
        audioRecordingCallback = null
        audioManager = null
        appChannel = null
        super.onDestroy()
        glassesPresentation?.dismiss()
        glassesEngine?.destroy()
        glassesChannel = null
    }

    private fun saveLogsToFile() {
        try {
            Log.d("SmartWear", "Starting to save logs...")

            // Сохраняем все логи
            val processAll = Runtime.getRuntime().exec("logcat -d")
            val readerAll = processAll.inputStream.bufferedReader()
            val allLogs = readerAll.use { it.readText() }
            readerAll.close()

            val fileAll = java.io.File(getExternalFilesDir(null), "full_logs.txt")
            fileAll.writeText(allLogs)

            // Сохраняем только DisplayInfo и SmartWear логи
            val processFiltered = Runtime.getRuntime().exec(arrayOf("sh", "-c", "logcat -d | grep -E '(DisplayInfo|SmartWear)'"))
            val readerFiltered = processFiltered.inputStream.bufferedReader()
            val filteredLogs = readerFiltered.use { it.readText() }
            readerFiltered.close()

            val fileFiltered = java.io.File(getExternalFilesDir(null), "display_logs.txt")
            fileFiltered.writeText(filteredLogs)

            val message = "Logs saved:\n${fileAll.absolutePath}\n${fileFiltered.absolutePath}"
            Log.d("SmartWear", message)

            // Показываем Toast с путем к файлам
            mainHandler.post {
                Toast.makeText(this, "Logs saved to:\n${fileAll.parent}", Toast.LENGTH_LONG).show()
            }
        } catch (e: Exception) {
            Log.e("SmartWear", "Failed to save logs: $e")
            mainHandler.post {
                Toast.makeText(this, "Failed to save logs: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun clearLogs() {
        try {
            Runtime.getRuntime().exec("logcat -c")
            Log.d("SmartWear", "Logcat cleared")
        } catch (e: Exception) {
            Log.e("SmartWear", "Failed to clear logs: $e")
        }
    }

    private fun logConnectedDisplays(context: Context) {
        val displayManager =
            context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

        val displays = displayManager.displays

        for (display in displays) {
            logDisplayInfo(context, display)
        }
    }

    private fun logDisplayInfo(context: Context, display: Display) {
        val displayId = display.displayId
        val name = display.name
        val flags = display.flags
        val rotation = display.rotation

        // Логическое разрешение
        val logicalSize = Point()
        display.getSize(logicalSize)

        // Реальное логическое разрешение, включая системные области
        val realSize = Point()
        display.getRealSize(realSize)

        // Физическое разрешение текущего режима дисплея
        val mode = display.mode
        val physicalWidth = mode.physicalWidth
        val physicalHeight = mode.physicalHeight
        val refreshRate = mode.refreshRate

        val isDefault = displayId == Display.DEFAULT_DISPLAY

        Log.d(
            "DisplayInfo",
            """
            Display:
              id=$displayId
              name=$name
              isDefault=$isDefault
              flags=$flags
              rotation=$rotation

              logical getSize=${logicalSize.x}x${logicalSize.y}
              logical getRealSize=${realSize.x}x${realSize.y}

              physical mode=${physicalWidth}x${physicalHeight}
              refreshRate=${refreshRate}Hz
            """.trimIndent()
        )
    }
}

class GlassesPresentation(
    context: Context,
    display: Display,
    private val flutterEngine: FlutterEngine
) : Presentation(context, display) {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))

        val flutterTextureView = FlutterTextureView(context)
        val flutterView = FlutterView(context, flutterTextureView)
        setContentView(flutterView)

        flutterView.attachToFlutterEngine(flutterEngine)
        flutterEngine.lifecycleChannel.appIsResumed()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        flutterEngine.lifecycleChannel.appIsPaused()
    }
}
