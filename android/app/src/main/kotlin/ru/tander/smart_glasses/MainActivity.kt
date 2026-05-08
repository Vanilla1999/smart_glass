package com.example.smart_wear_flutter_test

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.Point
import android.view.WindowInsets
import android.view.WindowManager
import android.os.Build
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

class MainActivity : FlutterFragmentActivity() {
    private var engineGroup: FlutterEngineGroup? = null
    private var glassesEngine: FlutterEngine? = null
    private var glassesChannel: MethodChannel? = null
    private var glassesPresentation: GlassesPresentation? = null
    private var displayManager: DisplayManager? = null
    private var currentCounter = 0
    private var currentRecognizedText = ""
    private val mainHandler = Handler(Looper.getMainLooper())

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app_channel")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showGlasses" -> {
                        Log.d("SmartWear", "showGlasses called with counter: $currentCounter")
                        currentCounter = call.arguments as? Int ?: 0
                        showGlasses()
                        result.success(true)
                    }
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
                    "showGlassesScreen2" -> {
                        Log.d("SmartWear", "showGlassesScreen2 called with counter: $currentCounter")
                        currentCounter = call.arguments as? Int ?: 0
                        showGlassesScreen2()
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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        displayManager = getSystemService(DISPLAY_SERVICE) as DisplayManager

        // Логируем информацию о всех подключенных дисплеях
        logConnectedDisplays(this)
    }

    private fun showGlasses() {
        Log.d("SmartWear", "showGlasses() called, currentCounter=$currentCounter")
        val displays = displayManager?.getDisplays()
        if (displays != null && displays.size > 1) {
            val secondaryDisplay = displays[displays.size - 1]

            glassesPresentation?.dismiss()
            // Engine is already pre-warmed, just create Presentation

            if (glassesEngine != null) {
                glassesPresentation = GlassesPresentation(this, secondaryDisplay, glassesEngine!!)
                glassesPresentation?.show()
                Log.d("SmartWear", "Glasses presentation shown, navigating to home")
                glassesChannel?.invokeMethod("navigateToRoute", "/")
                updateGlassesCounter(currentCounter)
                updateGlassesRecognizedText(currentRecognizedText)
            }
        } else {
            Log.d("SmartWear", "No secondary display found")
        }
    }

    private fun showGlassesInitialization() {
        Log.d("SmartWear", "showGlassesInitialization() called")
        val displays = displayManager?.getDisplays()
        if (displays != null && displays.size > 1) {
            val secondaryDisplay = displays[displays.size - 1]

            glassesPresentation?.dismiss()

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
        glassesChannel?.invokeMethod("navigateToRoute", "/empty")
    }

    private fun showGlassesScreen2() {
        Log.d("SmartWear", "showGlassesScreen2() called, currentCounter=$currentCounter")
        val displays = displayManager?.getDisplays()
        if (displays != null && displays.size > 1) {
            val secondaryDisplay = displays[displays.size - 1]

            if (glassesPresentation == null && glassesEngine != null) {
                glassesPresentation = GlassesPresentation(this, secondaryDisplay, glassesEngine!!)
                glassesPresentation?.show()
            }

            Log.d("SmartWear", "Navigating to screen 2 on glasses")
            val data = mapOf(
                "route" to "/screen2",
                "data" to mapOf(
                    "counter" to currentCounter,
                    "recognizedText" to currentRecognizedText
                )
            )
            glassesChannel?.invokeMethod("navigateToScreen", data)
        } else {
            Log.d("SmartWear", "No secondary display found")
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
