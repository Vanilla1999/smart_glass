package com.example.multi_scanner_example

import android.app.Presentation
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

class GlassesDisplayHelper(private val context: Context) {
    private var presentation: SimplePresentation? = null

    fun show(): Boolean {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val displays = dm.displays
        if (displays.size <= 1) {
            Log.w(TAG, "No secondary display found")
            return false
        }
        val secondary = displays[displays.size - 1]
        presentation?.dismiss()
        presentation = SimplePresentation(context, secondary)
        presentation?.show()
        Log.i(TAG, "Glasses presentation shown on display=${secondary.displayId}")
        return true
    }

    fun hide() {
        presentation?.dismiss()
        presentation = null
        Log.i(TAG, "Glasses presentation dismissed")
    }

    fun isShowing(): Boolean = presentation != null

    private class SimplePresentation(
        context: Context,
        display: Display,
    ) : Presentation(context, display) {
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            window?.setBackgroundDrawable(ColorDrawable(Color.BLACK))
            val view = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = android.view.Gravity.CENTER
                setBackgroundColor(Color.BLACK)
                addView(TextView(context).apply {
                    text = "Glasses Display Active"
                    setTextColor(Color.WHITE)
                    textSize = 20f
                })
            }
            setContentView(view)
        }
    }

    companion object {
        private const val TAG = "GlassesDisplayHelper"
    }
}
