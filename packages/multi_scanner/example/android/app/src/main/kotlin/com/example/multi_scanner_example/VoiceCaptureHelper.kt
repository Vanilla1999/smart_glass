package com.example.multi_scanner_example

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
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
import java.util.concurrent.TimeUnit

/**
 * Full voice scheme mirroring smart_glasses NativeVoiceCaptureManager:
 * SSP Config -> SDKActive.active -> SspManager.init -> UAC4 bind/init/start.
 */
class VoiceCaptureHelper(private val context: Context) {
    private var service: IUac4AppService? = null
    private var connection: ServiceConnection? = null
    private var bound = false
    @Volatile private var capturing = false
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

    private fun notifyState() { onStateChange?.let { android.os.Handler(android.os.Looper.getMainLooper()).post(it) } }

    private fun prepareSsp(): String? {
        return try {
            Config.setAppKey(BuildConfig.UAC4_APP_KEY)
            Config.setAppSecret(BuildConfig.UAC4_APP_SECRET)
            Config.setUdid(BuildConfig.UAC4_UDID)
            Config.setAiCode(AICodeType.AI_SSP_KWS_DICTATION_TTS_OFF)
            if (!activated) {
                val latch = CountDownLatch(1)
                var error: String? = null
                val accepted = SDKActive.getInstance().active(
                    context.applicationContext,
                    object : IActiveListener {
                        override fun success() {
                            activated = true
                            latch.countDown()
                        }
                        override fun onError(errorCode: Int, message: String?) {
                            error = "code=$errorCode message=$message"
                            latch.countDown()
                        }
                    }
                )
                if (!accepted) return "SDKActive.active returned false"
                if (!latch.await(ACTIVATION_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                    return "activation timeout"
                }
                error?.let { return "activation failed: $it" }
            }
            val initialized = SspManager.getInstance().init(context.applicationContext)
            if (!initialized) return "SspManager.init returned false"
            sspInitialized = true
            Log.i(TAG, "SSP: activated=$activated initialized=$sspInitialized")
            null
        } catch (e: Throwable) {
            Log.e(TAG, "SSP prepare failed", e)
            "SSP exception: ${e.message}"
        }
    }

    fun startCapture(): String {
        if (capturing) return "already capturing"
        Log.i(TAG, "UAC4: starting (full SSP scheme)")
        val sspError = prepareSsp()
        if (sspError != null) {
            Log.e(TAG, "SSP prepare error: $sspError")
            return "SSP error: $sspError"
        }
        val intent = Intent().setClassName(
            "com.xcheng.uac4client",
            "com.xcheng.uac4client.Uac4ClientService",
        )
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                Log.i(TAG, "UAC4: service connected")
                val svc = IUac4AppService.Stub.asInterface(binder)
                service = svc
                try {
                    val callback = object : IUac4AppCallback.Stub() {
                        override fun onAudioData(data: ByteArray) {
                            if (data.isEmpty()) return
                            pcmCount++
                            pcmBytes += data.size
                            var offset = 0
                            while (offset < data.size) {
                                val copy = minOf(
                                    data.size - offset,
                                    pcmAccumulator.size - pcmAccumulated,
                                )
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
                                    "UAC4 PCM: ${data.size} bytes (packet #$pcmCount, " +
                                        "total=${pcmBytes}, monoFrames=$monoFrames)",
                                )
                            }
                        }
                    }
                    val initResult = svc.initUac4(callback)
                    Log.i(TAG, "UAC4 initUac4 result=$initResult")
                    if (initResult != 0) return
                    SystemClock.sleep(UAC4_POST_INIT_SETTLE_MILLIS)
                    val startResult = svc.startUac4Mic()
                    Log.i(TAG, "UAC4 startUac4Mic result=$startResult")
                    if (startResult != 0) return
                    capturing = true
                    pcmCount = 0
                    pcmBytes = 0
                    monoFrames = 0
                    denoiser.reset()
                    notifyState()
                } catch (e: Exception) {
                    Log.e(TAG, "UAC4 start failed", e)
                }
            }
            override fun onServiceDisconnected(name: ComponentName?) {
                Log.w(TAG, "UAC4: service disconnected")
                service = null
                capturing = false
            }
        }
        val started = context.bindService(intent, conn, Context.BIND_AUTO_CREATE)
        if (!started) return "bindService failed"
        connection = conn
        bound = true
        return "starting"
    }

    fun stopCapture(): String {
        val svc = service
        if (svc != null) {
            try {
                val stopResult = svc.stopUac4Mic()
                Log.i(TAG, "UAC4 stopUac4Mic result=$stopResult")
                val deinitResult = svc.deinitUac4()
                Log.i(TAG, "UAC4 deinitUac4 result=$deinitResult")
            } catch (e: Exception) {
                Log.e(TAG, "UAC4 stop failed", e)
            }
        }
        service = null
        capturing = false
        if (bound && connection != null) {
            try { context.unbindService(connection!!) } catch (_: Exception) {}
        }
        bound = false
        connection = null
        if (sspInitialized) {
            try {
                SspManager.getInstance().release()
            } catch (e: Exception) {
                Log.e(TAG, "SSP release failed", e)
            }
            sspInitialized = false
        }
        // SDKActive.release() must never be called: process-scoped, resolves to a
        // conflicting native symbol on T2151.
        return "stopped"
    }

    fun isCapturing(): Boolean = capturing

    companion object {
        private const val TAG = "VoiceCaptureHelper"
        private const val ACTIVATION_TIMEOUT_SECONDS = 10L
        private const val UAC4_POST_INIT_SETTLE_MILLIS = 2_000L
    }
}
