package com.example.multi_scanner_example

import android.app.Presentation
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.util.Log
import android.view.Display
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine

/** Secondary-display path intentionally mirrors smart_glasses MainActivity. */
class GlassesDisplayHelper(
    private val context: Context,
    private val flutterEngine: FlutterEngine,
) {
    private var presentation: FlutterEnginePresentation? = null

    fun show(): Boolean {
        val displayManager =
            context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val displays = displayManager.displays
        if (displays.size <= 1) {
            Log.w(TAG, "No secondary display found")
            return false
        }
        val secondary = displays[displays.size - 1]
        presentation?.dismiss()
        presentation = FlutterEnginePresentation(
            context,
            secondary,
            flutterEngine,
        ) {
            presentation = null
        }
        presentation?.show()
        Log.i(
            TAG,
            "Secondary Flutter engine presentation shown display=${secondary.displayId}",
        )
        return true
    }

    fun hide() {
        presentation?.dismiss()
        presentation = null
        Log.i(TAG, "Secondary Flutter engine presentation dismissed")
    }

    fun isShowing(): Boolean = presentation != null

    private class FlutterEnginePresentation(
        context: Context,
        display: Display,
        private val flutterEngine: FlutterEngine,
        private val onDetached: () -> Unit,
    ) : Presentation(context, display) {
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            val textureView = FlutterTextureView(context)
            val flutterView = FlutterView(context, textureView)
            setContentView(flutterView)
            flutterView.attachToFlutterEngine(flutterEngine)
            flutterEngine.lifecycleChannel.appIsResumed()
        }

        override fun onDetachedFromWindow() {
            super.onDetachedFromWindow()
            flutterEngine.lifecycleChannel.appIsPaused()
            onDetached()
        }
    }

    companion object {
        private const val TAG = "GlassesDisplayHelper"
    }
}
