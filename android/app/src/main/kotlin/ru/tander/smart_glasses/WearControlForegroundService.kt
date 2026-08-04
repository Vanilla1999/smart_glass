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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the existing Activity-owned Flutter/Vosk Wear runtime eligible to run
 * while the phone screen is off. This service does not own a FlutterEngine or
 * recognizer and deliberately stops when MainActivity is no longer usable.
 */
class WearControlForegroundService : Service() {
    companion object {
        private const val TAG = "SmartWear"
        private const val CHANNEL_ID = "wear_control"
        private const val NOTIFICATION_ID = 1002

        // A bounded lease prevents an orphaned process from holding the CPU
        // indefinitely if lifecycle cleanup is skipped by an unexpected path.
        private const val WAKE_LOCK_LEASE_MS = 10 * 60 * 1000L
        private const val WAKE_LOCK_RENEW_AFTER_MS = 9 * 60 * 1000L

        fun start(context: Context) {
            Log.d(TAG, "Wear screen-off service start requested")
            ContextCompat.startForegroundService(
                context,
                Intent(context, WearControlForegroundService::class.java),
            )
        }

        fun stop(context: Context) {
            Log.d(TAG, "Wear screen-off service stop requested")
            context.stopService(Intent(context, WearControlForegroundService::class.java))
        }
    }

    private var receiverRegistered = false
    private var foregroundStarted = false
    private var initialized = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val renewWakeLock = Runnable {
        if (!MainActivity.isWearRuntimeAvailable()) {
            Log.w(TAG, "Stopping screen-off service: Flutter activity unavailable")
            stopSelf()
            return@Runnable
        }
        if (!refreshWakeLockLease()) {
            Log.e(TAG, "Stopping screen-off service: wake lock lease renewal failed")
            stopSelf()
        }
    }

    private val buttonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != WearButtonCommandPolicy.ACTION) return
            val observedSender = observedSenderPackage()
            if (!WearButtonCommandPolicy.acceptsObservedSender(
                    observedPackage = observedSender,
                    ownPackage = packageName,
                )
            ) {
                Log.w(TAG, "Ignoring button broadcast from package=$observedSender")
                return
            }
            val value = WearButtonCommandPolicy.normalize(
                intent.getStringExtra(WearButtonCommandPolicy.VALUE_EXTRA),
            )
            if (value == null) {
                Log.w(TAG, "Ignoring invalid Wear button broadcast")
                return
            }
            Log.d(TAG, "Screen-off button broadcast received: $value")
            if (!MainActivity.dispatchWearButtonCommand(value)) {
                Log.w(TAG, "Stopping screen-off service: command target unavailable")
                stopSelf()
            }
        }

        private fun observedSenderPackage(): String? {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                sentFromPackage
            } else {
                null
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
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
                .setContentText("Работает при выключенном экране в текущей Wear-сессии")
                .setContentIntent(openApp)
                .setOngoing(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .build()
            startForeground(NOTIFICATION_ID, notification)
            foregroundStarted = true

            if (!MainActivity.isWearRuntimeAvailable() || !refreshWakeLockLease()) {
                Log.w(TAG, "Screen-off service started without an enabled Flutter runtime")
                stopSelf()
                return
            }

            val filter = IntentFilter(WearButtonCommandPolicy.ACTION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // The vendor UAC4 application emits this legacy broadcast, so this
                // receiver cannot be NOT_EXPORTED until that external contract is
                // replaced by an explicit/signature-protected channel.
                registerReceiver(buttonReceiver, filter, RECEIVER_EXPORTED)
            } else {
                registerReceiver(buttonReceiver, filter)
            }
            receiverRegistered = true
            initialized = true
        } catch (error: RuntimeException) {
            Log.e(TAG, "Unable to initialize Wear screen-off service", error)
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!initialized ||
            !MainActivity.isWearRuntimeAvailable() ||
            !refreshWakeLockLease()
        ) {
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "Wear task removed; stopping screen-off service")
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(renewWakeLock)
        if (receiverRegistered) {
            try {
                unregisterReceiver(buttonReceiver)
            } catch (error: IllegalArgumentException) {
                Log.w(TAG, "Wear button receiver was already unregistered", error)
            }
            receiverRegistered = false
        }
        initialized = false
        releaseWakeLock()
        if (foregroundStarted) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foregroundStarted = false
        }
        Log.d(TAG, "Wear screen-off service destroyed")
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

    private fun refreshWakeLockLease(): Boolean {
        mainHandler.removeCallbacks(renewWakeLock)
        return try {
            val lock = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "smart_glasses:WearControlRuntime",
                )
                .also {
                    it.setReferenceCounted(false)
                    wakeLock = it
                }
            lock.acquire(WAKE_LOCK_LEASE_MS)
            mainHandler.postDelayed(renewWakeLock, WAKE_LOCK_RENEW_AFTER_MS)
            Log.d(TAG, "Wear control wake lock lease refreshed")
            true
        } catch (error: RuntimeException) {
            Log.e(TAG, "Wear control wake lock acquire failed", error)
            releaseWakeLock()
            false
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        try {
            if (lock.isHeld) {
                lock.release()
                Log.d(TAG, "Wear control wake lock released")
            }
        } catch (error: RuntimeException) {
            Log.e(TAG, "Wear control wake lock release failed", error)
        } finally {
            wakeLock = null
        }
    }
}
