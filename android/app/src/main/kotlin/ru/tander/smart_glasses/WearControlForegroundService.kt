package ru.tander.smart_glasses

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class WearControlForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "wear_control"
        private const val NOTIFICATION_ID = 1002
        private const val BUTTON_ACTION = "test"
        private const val BUTTON_VALUE = "value"

        fun start(context: Context) {
            Log.d("SmartWear", "Wear control service start requested")
            ContextCompat.startForegroundService(
                context,
                Intent(context, WearControlForegroundService::class.java),
            )
        }

        fun stop(context: Context) {
            Log.d("SmartWear", "Wear control service stop requested")
            context.stopService(Intent(context, WearControlForegroundService::class.java))
        }
    }

    private var receiverRegistered = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val buttonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val value = intent?.getStringExtra(BUTTON_VALUE)?.lowercase() ?: return
            if (value !in setOf("up", "down", "enter")) {
                Log.w("SmartWear", "Ignoring button broadcast value=$value")
                return
            }
            Log.d("SmartWear", "Background button broadcast received: $value")
            MainActivity.dispatchWearButtonCommand(value)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Управление очками активно")
            .setContentText("Кнопки вверх, вниз и выбрать доступны в фоне")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        acquireWakeLock()

        val filter = IntentFilter(BUTTON_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(buttonReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(buttonReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onDestroy() {
        if (receiverRegistered) {
            unregisterReceiver(buttonReceiver)
            receiverRegistered = false
        }
        releaseWakeLock()
        Log.d("SmartWear", "Wear control service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Управление очками",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        try {
            val lock = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "smart_glasses:WearControlRuntime",
                )
                .also {
                    it.setReferenceCounted(false)
                    wakeLock = it
                }
            if (!lock.isHeld) {
                lock.acquire()
                Log.d("SmartWear", "Wear control wake lock acquired")
            }
        } catch (error: RuntimeException) {
            Log.e("SmartWear", "Wear control wake lock acquire failed", error)
            releaseWakeLock()
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        try {
            if (lock.isHeld) {
                lock.release()
                Log.d("SmartWear", "Wear control wake lock released")
            }
        } catch (error: RuntimeException) {
            Log.e("SmartWear", "Wear control wake lock release failed", error)
        } finally {
            wakeLock = null
        }
    }
}
