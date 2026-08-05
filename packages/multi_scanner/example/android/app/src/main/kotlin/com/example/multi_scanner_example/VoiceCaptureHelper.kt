package com.example.multi_scanner_example

import ru.tander.smart_glasses.BuildConfig
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.unisound.active.AICodeType
import com.unisound.active.Config
import com.unisound.active.IActiveListener
import com.unisound.active.SDKActive
import com.unisound.ssp.SspManager
import com.xcheng.uac4client.IUac4AppCallback
import com.xcheng.uac4client.IUac4AppService
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * UAC4/SSP harness with the same important scheduling shape as the production
 * NativeVoiceCaptureManager: all vendor work runs away from Android's main
 * thread, so ViScanner.init/prepare can overlap it.
 */
class VoiceCaptureHelper(private val context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "main-parity-uac4").apply { isDaemon = true }
    }
    private val stateLock = Any()

    @Volatile private var service: IUac4AppService? = null
    @Volatile private var connection: ServiceConnection? = null
    @Volatile private var bound = false
    @Volatile private var starting = false
    @Volatile private var capturing = false
    @Volatile private var closed = false
    private var activated = false
    private var sspInitialized = false
    private var pcmCount = 0
    private var pcmBytes = 0L
    private val denoiser = RawLightDenoiser()
    private val sspInput = ByteArray(RawLightDenoiser.INPUT_FRAME_BYTES)
    private val sspOutput = ByteArray(RawLightDenoiser.OUTPUT_FRAME_BYTES)
    private val pcmAccumulator = ByteArray(RawLightDenoiser.INPUT_FRAME_BYTES * 16)
    private var pcmAccumulated = 0
    private var monoFrames = 0
    var onStateChange: (() -> Unit)? = null

    fun startCapture(onComplete: (Result<String>) -> Unit) {
        synchronized(stateLock) {
            when {
                closed -> {
                    complete(onComplete, Result.failure(IllegalStateException("voice helper is closed")))
                    return
                }
                capturing -> {
                    complete(onComplete, Result.success("already capturing"))
                    return
                }
                starting -> {
                    complete(onComplete, Result.success("already starting"))
                    return
                }
                else -> starting = true
            }
        }

        worker.execute {
            val outcome = runCatching { startCaptureBlocking() }
            synchronized(stateLock) { starting = false }
            if (outcome.isFailure) {
                Log.e(TAG, "UAC4 parity start failed", outcome.exceptionOrNull())
                runCatching { stopCaptureBlocking() }
            }
            notifyState()
            complete(onComplete, outcome)
        }
    }

    fun stopCapture(onComplete: (Result<String>) -> Unit) {
        worker.execute {
            val outcome = runCatching { stopCaptureBlocking() }
            notifyState()
            complete(onComplete, outcome)
        }
    }

    private fun startCaptureBlocking(): String {
        Log.i(TAG, "UAC4 parity start: worker=${Thread.currentThread().name}")
        prepareSsp()

        val connected = CountDownLatch(1)
        var connectedBinder: IBinder? = null
        val intent = Intent().setClassName(UAC4_PACKAGE, UAC4_CLASS)
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                connectedBinder = binder
                connected.countDown()
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                Log.w(TAG, "UAC4 service disconnected")
                service = null
                bound = false
                capturing = false
                notifyState()
            }
        }
        connection = conn
        if (!appContext.bindService(intent, conn, Context.BIND_AUTO_CREATE)) {
            connection = null
            throw IllegalStateException("bindService failed")
        }
        bound = true
        if (!connected.await(SERVICE_BIND_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw IllegalStateException("UAC4 service bind timeout")
        }
        val binder = connectedBinder
            ?: throw IllegalStateException("UAC4 service returned a null binder")
        val svc = IUac4AppService.Stub.asInterface(binder)
        service = svc

        val callback = object : IUac4AppCallback.Stub() {
            override fun onAudioData(data: ByteArray) {
                processPcm(data)
            }
        }
        val initResult = svc.initUac4(callback)
        Log.i(TAG, "UAC4 initUac4 result=$initResult")
        if (initResult != 0) {
            throw IllegalStateException("initUac4 result=$initResult")
        }
        SystemClock.sleep(UAC4_POST_INIT_SETTLE_MILLIS)
        val startResult = svc.startUac4Mic()
        Log.i(TAG, "UAC4 startUac4Mic result=$startResult")
        if (startResult != 0) {
            throw IllegalStateException("startUac4Mic result=$startResult")
        }

        pcmCount = 0
        pcmBytes = 0
        monoFrames = 0
        pcmAccumulated = 0
        denoiser.reset()
        capturing = true
        Log.i(TAG, "UAC4 parity capture active")
        return "capturing"
    }

    private fun prepareSsp() {
        Config.setAppKey(BuildConfig.UAC4_APP_KEY)
        Config.setAppSecret(BuildConfig.UAC4_APP_SECRET)
        Config.setUdid(BuildConfig.UAC4_UDID)
        Config.setAiCode(AICodeType.AI_SSP_KWS_DICTATION_TTS_OFF)
        if (!activated) {
            val latch = CountDownLatch(1)
            var activationError: String? = null
            val accepted = SDKActive.getInstance().active(
                appContext,
                object : IActiveListener {
                    override fun success() {
                        activated = true
                        latch.countDown()
                    }

                    override fun onError(errorCode: Int, message: String?) {
                        activationError = "code=$errorCode message=$message"
                        latch.countDown()
                    }
                },
            )
            if (!accepted) throw IllegalStateException("SDKActive.active returned false")
            if (!latch.await(ACTIVATION_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw IllegalStateException("activation timeout")
            }
            activationError?.let { throw IllegalStateException("activation failed: $it") }
        }
        if (!SspManager.getInstance().init(appContext)) {
            throw IllegalStateException("SspManager.init returned false")
        }
        sspInitialized = true
        Log.i(TAG, "SSP ready activated=$activated initialized=$sspInitialized")
    }

    private fun processPcm(data: ByteArray) {
        if (data.isEmpty()) return
        pcmCount++
        pcmBytes += data.size
        var offset = 0
        while (offset < data.size) {
            val copy = minOf(data.size - offset, pcmAccumulator.size - pcmAccumulated)
            System.arraycopy(data, offset, pcmAccumulator, pcmAccumulated, copy)
            pcmAccumulated += copy
            offset += copy
            if (pcmAccumulated >= RawLightDenoiser.INPUT_FRAME_BYTES) {
                System.arraycopy(
                    pcmAccumulator,
                    0,
                    sspInput,
                    0,
                    RawLightDenoiser.INPUT_FRAME_BYTES,
                )
                val written = denoiser.process(sspInput, sspOutput)
                if (written > 0) monoFrames++
                pcmAccumulated -= RawLightDenoiser.INPUT_FRAME_BYTES
                if (pcmAccumulated > 0) {
                    System.arraycopy(
                        pcmAccumulator,
                        RawLightDenoiser.INPUT_FRAME_BYTES,
                        pcmAccumulator,
                        0,
                        pcmAccumulated,
                    )
                }
            }
        }
        if (pcmCount % 50 == 1) {
            Log.i(
                TAG,
                "UAC4 PCM: ${data.size} bytes packet=$pcmCount total=$pcmBytes " +
                    "monoFrames=$monoFrames",
            )
        }
    }

    private fun stopCaptureBlocking(): String {
        val svc = service
        service = null
        capturing = false
        starting = false
        var firstFailure: Throwable? = null
        if (svc != null) {
            try {
                val stopResult = svc.stopUac4Mic()
                Log.i(TAG, "UAC4 stopUac4Mic result=$stopResult")
                if (stopResult != 0) {
                    firstFailure = IllegalStateException("stopUac4Mic result=$stopResult")
                }
            } catch (error: Throwable) {
                firstFailure = error
            }
            try {
                val deinitResult = svc.deinitUac4()
                Log.i(TAG, "UAC4 deinitUac4 result=$deinitResult")
                if (deinitResult != 0 && firstFailure == null) {
                    firstFailure = IllegalStateException("deinitUac4 result=$deinitResult")
                }
            } catch (error: Throwable) {
                if (firstFailure == null) firstFailure = error
            }
        }
        val activeConnection = connection
        connection = null
        if (bound && activeConnection != null) {
            try {
                appContext.unbindService(activeConnection)
            } catch (_: IllegalArgumentException) {
                // Already disconnected.
            }
        }
        bound = false
        if (sspInitialized) {
            try {
                SspManager.getInstance().release()
            } catch (error: Throwable) {
                if (firstFailure == null) firstFailure = error
            }
            sspInitialized = false
        }
        // SDKActive is process-scoped and intentionally remains activated.
        firstFailure?.let { throw it }
        return "stopped"
    }

    fun diagnostics(): Map<String, Any> = mapOf(
        "starting" to starting,
        "capturing" to capturing,
        "bound" to bound,
        "serviceConnected" to (service != null),
        "activated" to activated,
        "sspInitialized" to sspInitialized,
        "pcmPackets" to pcmCount,
        "pcmBytes" to pcmBytes,
        "monoFrames" to monoFrames,
        "worker" to "main-parity-uac4",
    )

    fun isCapturing(): Boolean = capturing

    fun close() {
        synchronized(stateLock) {
            if (closed) return
            closed = true
        }
        worker.execute {
            runCatching { stopCaptureBlocking() }
                .onFailure { Log.e(TAG, "UAC4 close failed", it) }
            worker.shutdown()
        }
    }

    private fun notifyState() {
        onStateChange?.let { callback -> mainHandler.post(callback) }
    }

    private fun complete(
        callback: (Result<String>) -> Unit,
        result: Result<String>,
    ) {
        mainHandler.post { callback(result) }
    }

    companion object {
        private const val TAG = "VoiceCaptureHelper"
        private const val UAC4_PACKAGE = "com.xcheng.uac4client"
        private const val UAC4_CLASS = "com.xcheng.uac4client.Uac4ClientService"
        private const val ACTIVATION_TIMEOUT_SECONDS = 10L
        private const val SERVICE_BIND_TIMEOUT_SECONDS = 5L
        private const val UAC4_POST_INIT_SETTLE_MILLIS = 2_000L
    }
}
