package ru.tander.smart_glasses

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.os.Build
import android.util.Log
import com.unisound.active.AICodeType
import com.unisound.active.Config
import com.unisound.active.IActiveListener
import com.unisound.active.SDKActive
import com.unisound.ssp.SspManager
import com.xcheng.uac4client.IUac4AppCallback
import com.xcheng.uac4client.IUac4AppService
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicLong
import ru.tander.smart_glasses.voice.PcmRingBuffer
import ru.tander.smart_glasses.voice.PcmMetrics
import ru.tander.smart_glasses.voice.SignalMetrics
import ru.tander.smart_glasses.voice.ByteBudget
import ru.tander.smart_glasses.voice.CaptureLeaseState
import ru.tander.smart_glasses.voice.DeliveryKey
import ru.tander.smart_glasses.voice.DrainSignal
import ru.tander.smart_glasses.voice.GenerationGate
import ru.tander.smart_glasses.voice.PcmAckProtocol
import ru.tander.smart_glasses.voice.PcmAcknowledgement
import ru.tander.smart_glasses.voice.PendingDeliveryState
import ru.tander.smart_glasses.voice.ProcessTerminalGate
import ru.tander.smart_glasses.voice.LateInitCleanupGate
import ru.tander.smart_glasses.voice.PcmStreamingGate
import ru.tander.smart_glasses.voice.RawLightDenoiser

private const val VOICE_CHANNEL = "ru.tander.smart_glasses/native_voice/control"
private const val PCM_CHANNEL = "ru.tander.smart_glasses/native_voice/pcm"
private const val EVENT_CHANNEL = "ru.tander.smart_glasses/native_voice/events"
private const val VOICE_TAG = "NativeVoiceCapture"
private const val UAC4_PACKAGE = "com.xcheng.uac4client"
private const val UAC4_CLASS = "com.xcheng.uac4client.Uac4ClientService"
private const val SSP_FRAME_BYTES = 2048
private const val PCM_HEADER_BYTES = 40
private const val UAC4_PACKET_BYTES = 32 * 1024
private const val MONO_PACKET_BYTES = SSP_FRAME_BYTES / 4 * 2
private const val MAX_PENDING_INPUT_BYTES = UAC4_PACKET_BYTES * 8
private const val ACTIVATION_TIMEOUT_SECONDS = 10L
private const val SERVICE_BIND_TIMEOUT_SECONDS = 5L
private const val UAC4_INIT_TIMEOUT_SECONDS = 10L
private const val UAC4_POST_INIT_SETTLE_MILLIS = 2_000L
private const val UAC4_START_TIMEOUT_SECONDS = 5L
private const val UAC4_STOP_TIMEOUT_SECONDS = 5L
private const val UAC4_DEINIT_TIMEOUT_SECONDS = 5L
private const val SSP_OPERATION_TIMEOUT_SECONDS = 5L
private const val SSP_PROCESS_TIMEOUT_MILLIS = 500L
internal const val PCM_ACK_TIMEOUT_MILLIS = 2_000L
private val VALID_OWNERS = setOf("wearRecognition", "legacyRecognition", "voiceMemo")

/** Owns the only UAC4 service lease in the primary Flutter engine. */
class NativeVoiceCapturePlugin(
    private val context: Context,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private val nextAttachmentId = AtomicLong(1)
        @Volatile private var sharedManager: NativeVoiceCaptureManager? = null

        private fun manager(context: Context): NativeVoiceCaptureManager =
            sharedManager ?: synchronized(this) {
                sharedManager ?: NativeVoiceCaptureManager(context.applicationContext).also {
                    sharedManager = it
                }
            }
    }

    private val methodChannel = MethodChannel(messenger, VOICE_CHANNEL)
    private val pcmChannel = BasicMessageChannel<ByteBuffer>(messenger, PCM_CHANNEL, BinaryCodec.INSTANCE)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val attachmentId = nextAttachmentId.getAndIncrement()
    @Volatile private var eventSink: EventChannel.EventSink? = null
    private val manager = manager(context)

    init {
        manager.attach(
            attachmentId,
            { packet, acknowledged ->
                mainHandler.post {
                    val direct = ByteBuffer.allocateDirect(packet.size).put(packet)
                    pcmChannel.send(direct) { reply -> acknowledged(PcmAckProtocol.decode(reply)) }
                }
            },
            { event -> mainHandler.post { eventSink?.success(event) } },
        )
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(manager.capabilities())
            "requestClientRecordAudioPermission" -> result.success(true)
            "prepare" -> manager.submit(result) { manager.prepare() }
            "start" -> {
                val owner = call.argument<String>("owner")
                if (owner == null || owner !in VALID_OWNERS) {
                    result.error("INVALID_OWNER", "owner must be one of $VALID_OWNERS", null)
                } else {
                    val recordDiagnosticWav = call.argument<Boolean>("recordDiagnosticWav") == true
                    val diagnosticCaptureTimestamp = call.argument<Number>("diagnosticCaptureTimestamp")?.toLong()
                    manager.submit(result) {
                        manager.start(owner, recordDiagnosticWav, diagnosticCaptureTimestamp)
                    }
                }
            }
            "confirmStart" -> {
                val leaseId = call.argument<Number>("leaseId")?.toLong()
                val revision = call.argument<Number>("captureRevision")?.toLong()
                if (leaseId == null || revision == null) {
                    result.error("INVALID_START_CONFIRMATION", "leaseId and captureRevision are required", null)
                } else {
                    manager.submit(result) { manager.confirmStart(leaseId, revision) }
                }
            }
            "stop" -> {
                val owner = call.argument<String>("owner")
                val leaseId = call.argument<Number>("leaseId")?.toLong()
                if (owner == null || owner !in VALID_OWNERS || leaseId == null) {
                    result.error("INVALID_STOP", "owner and leaseId are required", null)
                } else {
                    manager.submit(result) { manager.stop(owner, leaseId) }
                }
            }
            "getDiagnostics" -> result.success(manager.diagnostics())
            "detach" -> manager.submit(result) { manager.detach(); mapOf("detached" to true) }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        manager.detachAttachment(attachmentId)
    }

}

private class NativeVoiceCaptureManager(
    private val context: Context,
) {
    private val workerThread = HandlerThread("native-uac4-capture").apply { start() }
    private val worker = Handler(workerThread.looper)
    private val vendorExecutor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "native-uac4-vendor").apply { isDaemon = true }
    }
    private var attachmentId: Long? = null
    private var publishPacket: ((ByteArray, (PcmAcknowledgement?) -> Unit) -> Unit)? = null
    private var publishEvent: ((Map<String, Any?>) -> Unit)? = null
    private val inputLock = Any()
    private val inputQueue = ArrayDeque<CaptureInput>()
    private val inputBudget = ByteBudget(MAX_PENDING_INPUT_BYTES)
    private val inputBuffer = PcmRingBuffer(MAX_PENDING_INPUT_BYTES)
    private val inputTimestampSpans = ArrayDeque<InputTimestampSpan>()
    private var lastPublishedSourceTimestampNanos = 0L
    private val sspInput = ByteArray(SSP_FRAME_BYTES)
    private val sspOutput = ByteArray(SSP_FRAME_BYTES / 4)
    private val rawLightDenoiser = RawLightDenoiser()
    private val monoPacket = ByteArray(MONO_PACKET_BYTES)
    private val drainSignal = DrainSignal()
    private var service: IUac4AppService? = null
    private var connection: ServiceConnection? = null
    private var bound = false
    private var initialized = false
    private var initializedAtMs: Long? = null
    private var uac4InitAttempted = false
    private var activated = false
    private var sspInitialized = false
    private val leaseState = CaptureLeaseState()
    private val activeOwner: String? get() = leaseState.active?.owner
    private val activeLeaseId: Long? get() = leaseState.active?.leaseId
    private val captureRevision: Long get() = leaseState.revision
    private var nextSequence = 0L
    private val pcmStreamingGate = PcmStreamingGate()
    private var pendingDeliveryStartedAtMs: Long? = null
    private var firstCallbackAtMs: Long? = null
    private var captureStartedAtMs: Long? = null
    @Volatile private var dartReady = false
    private var preReadyCallbacks = 0L
    private var disposed = false
    private val delivery = PendingDeliveryState()
    private var ackTimeout: Runnable? = null
    private val callbackGate = GenerationGate()
    private val bindGate = GenerationGate()
    private var lateCallbacks = 0L
    private var callbackWatchdog: Runnable? = null
    private var inputMetrics = List(4) { SignalMetrics(0.0, 0.0, 0.0) }
    private var outputMetrics = SignalMetrics(0.0, 0.0, 0.0)
    private var binder: IBinder? = null
    private var deathRecipient: IBinder.DeathRecipient? = null
    private var rawDiagnosticWav: DiagnosticWavFile? = null

    fun attach(
        id: Long,
        packetPublisher: (ByteArray, (PcmAcknowledgement?) -> Unit) -> Unit,
        eventPublisher: (Map<String, Any?>) -> Unit,
    ) {
        worker.post {
            if (attachmentId != null && attachmentId != id) {
                try { detach() } catch (error: VoiceCaptureException) {
                    Log.e(VOICE_TAG, "previous engine cleanup failed", error)
                }
            }
            attachmentId = id
            publishPacket = packetPublisher
            publishEvent = eventPublisher
        }
    }

    fun detachAttachment(id: Long) {
        worker.post {
            if (attachmentId != id) return@post
            try { detach() } catch (error: VoiceCaptureException) {
                Log.e(VOICE_TAG, "engine detach cleanup failed", error)
            } finally {
                attachmentId = null
                publishPacket = null
                publishEvent = null
            }
        }
    }

    private fun callback(generation: Long) = object : IUac4AppCallback.Stub() {
        override fun onAudioData(data: ByteArray) {
            if (data.isEmpty()) return
            if (firstCallbackAtMs == null) {
                firstCallbackAtMs = SystemClock.elapsedRealtime()
                emitDiagnostic("firstVendorPcm", packetBytes = data.size)
            }
            if (!dartReady) {
                preReadyCallbacks++
                return
            }
            var overrun = false
            val shouldDrain = synchronized(inputLock) {
                if (!callbackGate.accepts(generation) || activeLeaseId == null) {
                    lateCallbacks++
                    false
                } else if (!inputBudget.acquire(data.size)) {
                    overrun = true
                    false
                } else {
                    inputQueue.addLast(
                        CaptureInput(
                            data.copyOf(),
                            generation,
                            captureRevision,
                            SystemClock.elapsedRealtimeNanos(),
                            System.currentTimeMillis() * 1_000L,
                        ),
                    )
                    drainSignal.request()
                }
            }
            if (shouldDrain) {
                worker.post(::drainInput)
            } else if (overrun) {
                worker.post {
                    terminateCapture(
                        "PCM_QUEUE_OVERRUN",
                        pcmQueueDetails("callback_budget", data.size),
                    )
                }
            }
            if (!overrun) worker.post { armCallbackWatchdog(generation) }
        }
    }

    fun capabilities(): Map<String, Any> {
        val available = context.packageManager.resolveService(
            Intent().setClassName(UAC4_PACKAGE, UAC4_CLASS),
            0,
        ) != null
        return mapOf(
            "serviceAvailable" to available,
            "servicePackage" to UAC4_PACKAGE,
            "serviceClass" to UAC4_CLASS,
            "abi" to Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
            "sampleRate" to 16000,
            "inputChannels" to 4,
            "outputChannels" to 1,
            "sspFrameBytes" to SSP_FRAME_BYTES,
            "permissionOwner" to "externalService",
            "clientRecordAudioPermissionRequired" to false,
            "clientRecordAudioPermissionGranted" to true,
            "clientRecordAudioPermissionCanRequest" to false,
            "activationConfigured" to activationConfigured(),
            "activated" to activated,
            "sspInitialized" to sspInitialized,
        )
    }

    fun diagnostics(): Map<String, Any?> = mapOf(
        "bound" to bound,
        "initialized" to initialized,
        "initAttempted" to uac4InitAttempted,
        "serverExpected" to uac4InitAttempted,
        "activated" to activated,
        "sspInitialized" to sspInitialized,
        "terminalAbandoned" to ProcessTerminalGate.isTerminal,
        "terminalReason" to ProcessTerminalGate.reason,
        "owner" to activeOwner,
        "leaseId" to activeLeaseId,
        "revision" to captureRevision,
        "receivedPcmPackets" to pcmStreamingGate.acceptedPackets,
        "firstCallbackAgeMs" to firstCallbackAtMs?.let { SystemClock.elapsedRealtime() - it },
        "pendingPcm" to (delivery.pending != null),
        "pendingPcmSequence" to delivery.pending?.sequence,
        "pendingPcmAckAgeMs" to pendingDeliveryStartedAtMs?.let {
            SystemClock.elapsedRealtime() - it
        },
        "pendingInputBytes" to inputBuffer.size,
        "pendingCallbacks" to synchronized(inputLock) { inputQueue.size },
        "pendingCallbackBytes" to synchronized(inputLock) { inputBudget.used },
        "pendingTimestampSpans" to inputTimestampSpans.size,
            "lateCallbacks" to lateCallbacks,
            "preReadyCallbacks" to preReadyCallbacks,
        "inputChannels" to inputMetrics.mapIndexed { index, metrics ->
            mapOf("channel" to index, "rms" to metrics.rms, "peak" to metrics.peak)
        },
        "processedMono" to mapOf(
            "rms" to outputMetrics.rms,
            "peak" to outputMetrics.peak,
            "clippingRatio" to outputMetrics.clippingRatio,
        ),
    )

    fun submit(result: MethodChannel.Result, operation: () -> Map<String, Any>) {
        worker.post {
            try {
                result.success(operation())
            } catch (error: VoiceCaptureException) {
                result.error(error.code, error.message, null)
            } catch (error: Exception) {
                Log.e(VOICE_TAG, "native capture operation failed", error)
                result.error("NATIVE_CAPTURE_FAILED", error.message, null)
            }
        }
    }

    fun prepare(): Map<String, Any> {
        checkNotDisposed()
        try {
            if (!(capabilities()["serviceAvailable"] as Boolean)) {
                throw VoiceCaptureException("UNSUPPORTED_FIRMWARE", "Uac4ClientService is unavailable")
            }
            emitState("activating")
            prepareSsp()
            if (!bound) {
            val generation = bindGate.next()
            val latch = CountDownLatch(1)
            var connectedBinder: IBinder? = null
            val connection = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName?, value: IBinder?) {
                    synchronized(this) { if (bindGate.accepts(generation)) connectedBinder = value }
                    latch.countDown()
                }
                override fun onServiceDisconnected(name: ComponentName?) {
                    worker.post { if (bindGate.accepts(generation)) terminateCapture("SERVICE_DISCONNECTED") }
                }
            }
            val started = context.bindService(
                Intent().setClassName(UAC4_PACKAGE, UAC4_CLASS),
                connection,
                Context.BIND_AUTO_CREATE,
            )
            if (!started) throw VoiceCaptureException("SERVICE_BIND_FAILED", "Unable to bind Uac4ClientService")
            if (!latch.await(SERVICE_BIND_TIMEOUT_SECONDS, TimeUnit.SECONDS) || connectedBinder == null) {
                bindGate.invalidate()
                try { context.unbindService(connection) } catch (_: IllegalArgumentException) {}
                throw VoiceCaptureException("SERVICE_BIND_TIMEOUT", "Timed out binding Uac4ClientService")
            }
            this.connection = connection
            binder = connectedBinder
            service = IUac4AppService.Stub.asInterface(connectedBinder)
            val connected = connectedBinder!!
            val recipient = IBinder.DeathRecipient {
                worker.post {
                    if (bindGate.accepts(generation) && binder === connected) {
                        service = null
                        bound = false
                        initialized = false
                        initializedAtMs = null
                        terminateCapture("BINDER_DIED")
                    }
                }
            }
            deathRecipient = recipient
            connected.linkToDeath(recipient, 0)
            bound = true
            emitState("bound")
            }
            if (!initialized) {
                val generation = callbackGate.next()
                uac4InitAttempted = true
                emitDiagnostic("uac4InitStarted")
                val result = runUac4Init(generation)
                emitDiagnostic("uac4InitResult", vendorResult = result)
                if (result != 0) throw VoiceCaptureException("UAC4_INIT_FAILED", "Vendor result=$result")
                initialized = true
                initializedAtMs = SystemClock.elapsedRealtime()
                emitState("initialized")
            }
            return mapOf("prepared" to true)
        } catch (error: VoiceCaptureException) {
            if (!ProcessTerminalGate.isTerminal) rollbackPrepare()
            throw error
        }
    }

    fun start(
        owner: String,
        recordDiagnosticWav: Boolean,
        diagnosticCaptureTimestamp: Long?,
    ): Map<String, Any> {
        checkNotDisposed()
        if (activeLeaseId != null) throw VoiceCaptureException("CAPTURE_BUSY", "Capture is owned by $activeOwner")
        if (!initialized || !sspInitialized) prepare()
        val lease = leaseState.begin(owner)
        val leaseId = lease.leaseId
        nextSequence = 0L
        pcmStreamingGate.reset()
        firstCallbackAtMs = null
        captureStartedAtMs = SystemClock.elapsedRealtime()
        inputMetrics = List(4) { SignalMetrics(0.0, 0.0, 0.0) }
        outputMetrics = SignalMetrics(0.0, 0.0, 0.0)
        rawLightDenoiser.reset()
        clearInput()
        if (recordDiagnosticWav) {
            val timestamp = diagnosticCaptureTimestamp ?: System.currentTimeMillis()
            rawDiagnosticWav = DiagnosticWavFile(
                File(context.getExternalFilesDir(null), "voice_capture/raw_4ch_$timestamp.wav"),
                channels = 4,
            )
            Log.i(VOICE_TAG, "raw 4-channel WAV recording path=${rawDiagnosticWav!!.path}")
        }
        try {
            val settleRemaining = initializedAtMs?.let {
                UAC4_POST_INIT_SETTLE_MILLIS - (SystemClock.elapsedRealtime() - it)
            } ?: 0L
            if (settleRemaining > 0) SystemClock.sleep(settleRemaining)
            val result = runVendor("UAC4_START_FAILED", "UAC4_START_TIMEOUT", UAC4_START_TIMEOUT_SECONDS) { service?.startUac4Mic() }
            emitDiagnostic("uac4StartResult", vendorResult = result)
            if (result != 0) throw VoiceCaptureException("UAC4_START_FAILED", "Vendor result=$result")
        } catch (error: VoiceCaptureException) {
            closeDiagnosticWav()
            if (!ProcessTerminalGate.isTerminal) {
                invalidateCapture(owner, leaseId)
                rollbackPrepare()
            }
            throw error
        }
        armStartConfirmationWatchdog(callbackGate.generation)
        emitState("starting")
        return mapOf("leaseId" to leaseId, "captureRevision" to captureRevision)
    }

    fun confirmStart(leaseId: Long, revision: Long): Map<String, Any> {
        checkNotDisposed()
        if (activeLeaseId != leaseId || captureRevision != revision) {
            throw VoiceCaptureException("STALE_LEASE", "Capture start confirmation is stale")
        }
        dartReady = true
        armCallbackWatchdog(callbackGate.generation, 15_000L)
        emitState("waitingForPcm")
        scheduleDrain(force = true)
        return mapOf("waitingForPcm" to true)
    }

    fun stop(owner: String, leaseId: Long): Map<String, Any> {
        if (activeLeaseId == null && leaseState.lastCompleted?.leaseId == leaseId) {
            if (leaseState.lastCompleted?.owner != owner) throw VoiceCaptureException("OWNER_MISMATCH", "Lease belongs to ${leaseState.lastCompleted?.owner}")
            return mapOf("stopped" to false)
        }
        val active = activeLeaseId ?: throw VoiceCaptureException("STALE_LEASE", "No active capture")
        if (active != leaseId) throw VoiceCaptureException("STALE_LEASE", "Lease is not active")
        if (activeOwner != owner) throw VoiceCaptureException("OWNER_MISMATCH", "Lease belongs to $activeOwner")
        invalidateCapture(owner, leaseId)
        closeDiagnosticWav()
        var failure: VoiceCaptureException? = null
        try { requireVendorSuccess("UAC4_STOP_FAILED", "UAC4_STOP_TIMEOUT", UAC4_STOP_TIMEOUT_SECONDS) { service?.stopUac4Mic() } } catch (error: VoiceCaptureException) { failure = error }
        if (ProcessTerminalGate.isTerminal) throw failure!!
        try { deinitAndUnbind() } catch (error: VoiceCaptureException) { if (failure == null) failure = error }
        try { releaseSsp() } catch (error: VoiceCaptureException) { if (failure == null) failure = error }
        failure?.let {
            emitState("terminalAbandoned", errorCode = it.code, leaseId = leaseId, owner = owner)
            throw it
        }
        emitState("idle", leaseId = leaseId, owner = owner)
        return mapOf("stopped" to true)
    }

    fun detach() {
        if (disposed) return
        val owner = activeOwner
        val lease = activeLeaseId
        if (lease != null && owner != null) invalidateCapture(owner, lease) else invalidateDelivery()
        if (lease != null) {
            try { requireVendorSuccess("UAC4_STOP_FAILED", "UAC4_STOP_TIMEOUT", UAC4_STOP_TIMEOUT_SECONDS) { service?.stopUac4Mic() } } catch (error: VoiceCaptureException) {
                Log.e(VOICE_TAG, "stop during detach failed", error)
            }
        }
        closeDiagnosticWav()
        if (ProcessTerminalGate.isTerminal) throw VoiceCaptureException("TERMINAL_ABANDONED", "Vendor operation was abandoned: ${ProcessTerminalGate.reason}")
        var failure: VoiceCaptureException? = null
        try { deinitAndUnbind() } catch (error: VoiceCaptureException) { failure = error }
        try { releaseSsp() } catch (error: VoiceCaptureException) { if (failure == null) failure = error }
        failure?.let {
            emitState("terminalAbandoned", errorCode = it.code, leaseId = lease, owner = owner)
            throw it
        }
        emitState("idle", leaseId = lease, owner = owner)
    }

    private fun drainInput() {
        if (!dartReady) {
            synchronized(inputLock) { drainSignal.idle() }
            return
        }
        while (delivery.pending == null) {
            if (inputBuffer.size < SSP_FRAME_BYTES) {
                val input = synchronized(inputLock) {
                    if (inputQueue.isEmpty()) {
                        drainSignal.idle()
                        null
                    } else {
                        inputQueue.removeFirst()
                    }
                } ?: return
                if (input.revision != captureRevision || !callbackGate.accepts(input.callbackGeneration) || activeLeaseId == null) {
                    synchronized(inputLock) { inputBudget.release(input.bytes.size) }
                    continue
                }
                if (!inputBuffer.append(input.bytes)) {
                    terminateCapture(
                        "PCM_QUEUE_OVERRUN",
                        pcmQueueDetails("ring_buffer", input.bytes.size),
                    )
                    return
                }
                inputTimestampSpans.addLast(
                    InputTimestampSpan(
                        remainingBytes = input.bytes.size,
                        elapsedRealtimeNanos = input.elapsedRealtimeNanos,
                        capturedAtEpochMicros = input.capturedAtEpochMicros,
                    ),
                )
            }
            var monoPacketSize = 0
            var sourceElapsedRealtimeNanos = 0L
            var capturedAtEpochMicros = 0L
            while (monoPacketSize < MONO_PACKET_BYTES && inputBuffer.readFrame(sspInput)) {
                val sourceTimestamp = consumeInputTimestamp(SSP_FRAME_BYTES)
                if (sourceElapsedRealtimeNanos == 0L) {
                    sourceElapsedRealtimeNanos = sourceTimestamp.elapsedRealtimeNanos
                    capturedAtEpochMicros = sourceTimestamp.capturedAtEpochMicros
                }
                synchronized(inputLock) { inputBudget.release(SSP_FRAME_BYTES) }
                val leaseId = activeLeaseId ?: return
                inputMetrics = PcmMetrics.interleavedPcm16Le(sspInput, 4)
                rawDiagnosticWav?.write(sspInput)
                val written = rawLightDenoiser.process(sspInput, sspOutput)
                if (written <= 0 || written > sspOutput.size || written % 2 != 0) {
                    terminateCapture("INVALID_SSP_OUTPUT")
                    return
                }
                outputMetrics = PcmMetrics.interleavedPcm16Le(sspOutput, 1, written).single()
                if (monoPacketSize + written > monoPacket.size) {
                    terminateCapture("INVALID_SSP_OUTPUT")
                    return
                }
                sspOutput.copyInto(monoPacket, monoPacketSize, 0, written)
                monoPacketSize += written
            }
            if (monoPacketSize > 0) {
                val leaseId = activeLeaseId ?: return
                if (nextSequence == 0L) {
                    emitDiagnostic("firstProcessedPcm", packetBytes = monoPacketSize)
                }
                publishMono(
                    leaseId,
                    monoPacket,
                    monoPacketSize,
                    sourceElapsedRealtimeNanos,
                    capturedAtEpochMicros,
                )
            }
        }
    }

    private fun publishMono(
        leaseId: Long,
        pcm: ByteArray,
        pcmSize: Int,
        sourceElapsedRealtimeNanos: Long,
        capturedAtEpochMicros: Long,
    ) {
        val sequence = nextSequence++
        val packetTimestampNanos = maxOf(sourceElapsedRealtimeNanos, lastPublishedSourceTimestampNanos + 1L)
        lastPublishedSourceTimestampNanos = packetTimestampNanos
        val key = DeliveryKey(captureRevision, leaseId, sequence)
        if (!delivery.begin(key)) return
        pendingDeliveryStartedAtMs = SystemClock.elapsedRealtime()
        val packet = ByteBuffer.allocate(PCM_HEADER_BYTES + pcmSize).order(ByteOrder.BIG_ENDIAN)
            .putInt(2)
            .putInt(PCM_HEADER_BYTES)
            .putLong(leaseId)
            .putLong(sequence)
            .putLong(packetTimestampNanos)
            .putLong(capturedAtEpochMicros)
            .put(pcm, 0, pcmSize)
            .array()
        val publisher = publishPacket
        if (publisher == null) {
            delivery.settle(key)
            pendingDeliveryStartedAtMs = null
            terminateCapture("PCM_ACK_TIMEOUT")
            return
        }
        publisher(packet) { ack -> worker.post {
            if (delivery.pending != key) {
                return@post
            }
            if (ack == null || ack.leaseId != key.leaseId || ack.sequence != key.sequence) {
                delivery.settle(key)
                pendingDeliveryStartedAtMs = null
                cancelAckTimeout()
                terminateCapture("PCM_CONSUMER_REJECTED_2")
                return@post
            }
            delivery.settle(key)
            pendingDeliveryStartedAtMs = null
            cancelAckTimeout()
            if (ack.status != 0) {
                    terminateCapture(
                        if (ack.status == 4) "RECOGNITION_BACKLOG" else "INVALID_PCM_FRAME",
                    )
            } else {
                if (pcmStreamingGate.acceptValidPacket()) emitState("streaming")
                scheduleDrain(force = true)
            }
        } }
        ackTimeout = Runnable {
            if (delivery.settle(key)) {
                pendingDeliveryStartedAtMs = null
                terminateCapture("PCM_ACK_TIMEOUT")
            }
        }.also { worker.postDelayed(it, PCM_ACK_TIMEOUT_MILLIS) }
    }

    private fun scheduleDrain(force: Boolean = false) {
        val shouldDrain = synchronized(inputLock) {
            drainSignal.request(force)
        }
        if (shouldDrain) worker.post(::drainInput)
    }

    private fun clearInput() {
        inputBuffer.clear()
        inputTimestampSpans.clear()
        lastPublishedSourceTimestampNanos = 0L
        synchronized(inputLock) {
            inputQueue.clear()
            inputBudget.clear()
            drainSignal.idle()
        }
    }

    private fun consumeInputTimestamp(byteCount: Int): InputTimestampSpan {
        val first = inputTimestampSpans.first()
        var remaining = byteCount
        while (remaining > 0) {
            val span = inputTimestampSpans.first()
            val consumed = minOf(remaining, span.remainingBytes)
            span.remainingBytes -= consumed
            remaining -= consumed
            if (span.remainingBytes == 0) inputTimestampSpans.removeFirst()
        }
        return first
    }

    private fun invalidateCapture(owner: String, leaseId: Long) {
        leaseState.complete(owner, leaseId)
        dartReady = false
        callbackGate.invalidate()
        callbackWatchdog?.let(worker::removeCallbacks)
        callbackWatchdog = null
        invalidateDelivery()
        clearInput()
    }

    private fun invalidateDelivery() {
        delivery.invalidate()
        pendingDeliveryStartedAtMs = null
        cancelAckTimeout()
    }

    private fun pcmQueueDetails(stage: String, incomingBytes: Int): String {
        val nowNanos = SystemClock.elapsedRealtimeNanos()
        val (callbackCount, callbackBytes, oldestCallbackAgeMs) = synchronized(inputLock) {
            val oldestNanos = inputQueue.firstOrNull()?.elapsedRealtimeNanos
            Triple(
                inputQueue.size,
                inputBudget.used,
                oldestNanos?.let { (nowNanos - it).coerceAtLeast(0L) / 1_000_000L },
            )
        }
        val pending = delivery.pending
        val ackAgeMs = pendingDeliveryStartedAtMs?.let {
            SystemClock.elapsedRealtime() - it
        }
        return "stage=$stage incomingBytes=$incomingBytes " +
            "callbackCount=$callbackCount callbackBytes=$callbackBytes " +
            "callbackCapacityBytes=$MAX_PENDING_INPUT_BYTES " +
            "oldestCallbackAgeMs=$oldestCallbackAgeMs " +
            "ringBytes=${inputBuffer.size} timestampSpans=${inputTimestampSpans.size} " +
            "pendingAck=${pending != null} pendingSequence=${pending?.sequence} " +
            "pendingAckAgeMs=$ackAgeMs nextSequence=$nextSequence"
    }

    private fun cancelAckTimeout() {
        ackTimeout?.let(worker::removeCallbacks)
        ackTimeout = null
    }

    private fun armCallbackWatchdog(generation: Long, delayMs: Long = 500L) {
        if (!dartReady || !callbackGate.accepts(generation) || activeLeaseId == null) return
        callbackWatchdog?.let(worker::removeCallbacks)
        callbackWatchdog = Runnable {
            if (callbackGate.accepts(generation) && activeLeaseId != null) terminateCapture("PCM_TIMEOUT")
        }.also { worker.postDelayed(it, delayMs) }
    }

    private fun armStartConfirmationWatchdog(generation: Long) {
        callbackWatchdog?.let(worker::removeCallbacks)
        callbackWatchdog = Runnable {
            if (!dartReady && callbackGate.accepts(generation) && activeLeaseId != null) {
                terminateCapture("PCM_TIMEOUT")
            }
        }.also { worker.postDelayed(it, 15_000L) }
    }

    private fun deinitAndUnbind() {
        var failure: VoiceCaptureException? = null
        if (initialized || uac4InitAttempted) {
            try { requireVendorSuccess("UAC4_DEINIT_FAILED", "UAC4_DEINIT_TIMEOUT", UAC4_DEINIT_TIMEOUT_SECONDS) { service?.deinitUac4() } } catch (error: VoiceCaptureException) { failure = error }
            if (ProcessTerminalGate.isTerminal) throw failure!!
        }
        initialized = false
        initializedAtMs = null
        uac4InitAttempted = false
        binder?.let { linkedBinder ->
            deathRecipient?.let { recipient ->
                try { linkedBinder.unlinkToDeath(recipient, 0) } catch (_: Exception) {}
            }
        }
        deathRecipient = null
        binder = null
        val activeConnection = connection
        connection = null
        bindGate.invalidate()
        if (bound && activeConnection != null) {
            try { context.unbindService(activeConnection) } catch (_: IllegalArgumentException) {}
        }
        bound = false
        service = null
        failure?.let { throw it }
    }

    private fun prepareSsp() {
        if (sspInitialized) return
        if (!activationConfigured()) {
            throw VoiceCaptureException("ACTIVATION_FAILED", "UAC4 activation credentials are not configured")
        }
        Config.setAppKey(BuildConfig.UAC4_APP_KEY)
        Config.setAppSecret(BuildConfig.UAC4_APP_SECRET)
        Config.setUdid(BuildConfig.UAC4_UDID)
        Config.setAiCode(AICodeType.AI_SSP_KWS_DICTATION_TTS_OFF)
        if (!activated) activateSspSdk()
        val initialized = runVendor("SSP_INIT_FAILED", "SSP_INIT_FAILED", SSP_OPERATION_TIMEOUT_SECONDS) {
            SspManager.getInstance().init(context.applicationContext)
        }
        if (!initialized) {
            throw VoiceCaptureException("SSP_INIT_FAILED", "SspManager.init returned false")
        }
        sspInitialized = true
        emitState("sspInitialized")
    }

    private fun activateSspSdk() {
        val latch = CountDownLatch(1)
        var activationError: VoiceCaptureException? = null
        var activationSucceeded = false
        val accepted = runVendor("ACTIVATION_FAILED", "ACTIVATION_TIMEOUT", ACTIVATION_TIMEOUT_SECONDS) {
            SDKActive.getInstance().active(context.applicationContext, object : IActiveListener {
                override fun success() {
                    activationSucceeded = true
                    latch.countDown()
                }

                override fun onError(error: Int, message: String?) {
                    activationError = VoiceCaptureException(
                        "ACTIVATION_FAILED",
                        "Vendor activation failed: error=$error, message=${message.orEmpty()}",
                    )
                    latch.countDown()
                }
            })
        }
        if (!accepted) {
            throw VoiceCaptureException("ACTIVATION_FAILED", "SDKActive.active returned false")
        }
        if (!latch.await(ACTIVATION_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            enterTerminalAbandoned("ACTIVATION_TIMEOUT")
            throw VoiceCaptureException("ACTIVATION_TIMEOUT", "Timed out activating SSP SDK")
        }
        activationError?.let { throw it }
        if (!activationSucceeded) {
            throw VoiceCaptureException("ACTIVATION_FAILED", "Vendor activation did not succeed")
        }
        activated = true
    }

    private fun releaseSsp() {
        if (sspInitialized) {
            runVendor("SSP_RELEASE_FAILED", "SSP_RELEASE_FAILED", SSP_OPERATION_TIMEOUT_SECONDS) { SspManager.getInstance().release() }
            sspInitialized = false
        }
        // SDKActive is process-scoped. Vendor SDKActive.release() resolves to a
        // conflicting native symbol on T2151 and must never be called.
    }

    private fun activationConfigured(): Boolean =
        BuildConfig.UAC4_APP_KEY.isNotBlank() &&
            BuildConfig.UAC4_APP_SECRET.isNotBlank() &&
            BuildConfig.UAC4_UDID.isNotBlank()

    private fun terminateCapture(errorCode: String, errorDetails: String? = null) {
        val leaseId = activeLeaseId
        val owner = activeOwner
        if (errorDetails != null) {
            Log.e(VOICE_TAG, "$errorCode $errorDetails")
        }
        if (leaseId != null && owner != null) {
            invalidateCapture(owner, leaseId)
        } else {
            leaseState.invalidate()
            callbackGate.invalidate()
            callbackWatchdog?.let(worker::removeCallbacks)
            callbackWatchdog = null
            invalidateDelivery()
            clearInput()
        }
        if (ProcessTerminalGate.isTerminal) return
        closeDiagnosticWav()
        try {
            if (leaseId != null) requireVendorSuccess("UAC4_STOP_FAILED", "UAC4_STOP_TIMEOUT", UAC4_STOP_TIMEOUT_SECONDS) { service?.stopUac4Mic() }
        } catch (error: VoiceCaptureException) {
            Log.e(VOICE_TAG, "stop after $errorCode failed", error)
            if (ProcessTerminalGate.isTerminal) return
        }
        try { deinitAndUnbind() } catch (error: VoiceCaptureException) {
            Log.e(VOICE_TAG, "deinit after $errorCode failed", error)
        }
        try { releaseSsp() } catch (error: VoiceCaptureException) {
            Log.e(VOICE_TAG, "release after $errorCode failed", error)
            emitState("terminalAbandoned", errorCode = "SSP_RELEASE_FAILED", leaseId = leaseId, owner = owner)
            return
        }
        emitState(
            "error",
            errorCode = errorCode,
            errorDetails = errorDetails,
            leaseId = leaseId,
            owner = owner,
        )
    }

    private fun closeDiagnosticWav() {
        rawDiagnosticWav?.close()
        rawDiagnosticWav = null
    }

    private fun emitState(
        state: String,
        errorCode: String? = null,
        errorDetails: String? = null,
        leaseId: Long? = activeLeaseId,
        owner: String? = activeOwner,
    ) {
        publishEvent?.invoke(mapOf(
            "state" to state,
            "leaseId" to leaseId,
            "owner" to owner,
            "revision" to captureRevision,
            "timestampMs" to SystemClock.elapsedRealtime(),
            "errorCode" to errorCode,
            "errorDetails" to errorDetails,
        ))
    }

    private fun requireVendorSuccess(code: String, timeoutCode: String, timeoutSeconds: Long, operation: () -> Int?) {
        val result = runVendor(code, timeoutCode, timeoutSeconds, operation = operation)
        if (result != 0) throw VoiceCaptureException(code, "Vendor result=$result")
    }

    private fun <T> runVendor(
        code: String,
        timeoutCode: String,
        timeout: Long,
        unit: TimeUnit = TimeUnit.SECONDS,
        operation: () -> T,
    ): T {
        checkNotDisposed()
        val future: Future<T> = vendorExecutor.submit<T> { operation() }
        return try {
            future.get(timeout, unit)
        } catch (error: TimeoutException) {
            future.cancel(true)
            enterTerminalAbandoned(timeoutCode)
            throw VoiceCaptureException(timeoutCode, "Vendor operation timed out")
        } catch (error: ExecutionException) {
            val cause = error.cause ?: error
            throw VoiceCaptureException(code, cause.message ?: code)
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw VoiceCaptureException(code, "Vendor operation interrupted")
        }
    }

    private fun runUac4Init(generation: Long): Int? {
        checkNotDisposed()
        val cleanupGate = LateInitCleanupGate()
        val initService = service
        fun lateCleanup() {
            try {
                initService?.deinitUac4()
                Log.w(VOICE_TAG, "late UAC4 init completed; deinit invoked")
            } catch (error: Exception) {
                Log.e(VOICE_TAG, "late UAC4 init deinit failed", error)
            }
            worker.post { unbindAfterLateInit() }
        }
        val future = vendorExecutor.submit<Int?> {
            val result = initService?.initUac4(callback(generation))
            if (cleanupGate.claimCleanup()) lateCleanup()
            result
        }
        return try {
            future.get(UAC4_INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } catch (error: TimeoutException) {
            cleanupGate.abandon()
            if (future.isDone) vendorExecutor.submit { if (cleanupGate.claimCleanup()) lateCleanup() }
            enterTerminalAbandoned("UAC4_INIT_TIMEOUT")
            throw VoiceCaptureException("UAC4_INIT_TIMEOUT", "Vendor operation timed out")
        } catch (error: ExecutionException) {
            val cause = error.cause ?: error
            throw VoiceCaptureException("UAC4_INIT_FAILED", cause.message ?: "UAC4_INIT_FAILED")
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw VoiceCaptureException("UAC4_INIT_FAILED", "Vendor operation interrupted")
        }
    }

    private fun unbindAfterLateInit() {
        initialized = false
        initializedAtMs = null
        uac4InitAttempted = false
        binder?.let { linkedBinder -> deathRecipient?.let { try { linkedBinder.unlinkToDeath(it, 0) } catch (_: Exception) {} } }
        deathRecipient = null
        binder = null
        val activeConnection = connection
        connection = null
        bindGate.invalidate()
        if (bound && activeConnection != null) try { context.unbindService(activeConnection) } catch (_: IllegalArgumentException) {}
        bound = false
        service = null
    }

    private fun emitDiagnostic(event: String, vendorResult: Int? = null, packetBytes: Int = 0) {
        val elapsed = captureStartedAtMs?.let { SystemClock.elapsedRealtime() - it }
        Log.i(VOICE_TAG, "$event leaseId=$activeLeaseId revision=$captureRevision sequence=$nextSequence elapsedMs=$elapsed packetBytes=$packetBytes vendorResult=$vendorResult")
    }

    private fun enterTerminalAbandoned(errorCode: String) {
        if (!ProcessTerminalGate.abandon(errorCode)) return
        val lease = activeLeaseId
        val owner = activeOwner
        bindGate.invalidate()
        if (lease != null && owner != null) invalidateCapture(owner, lease) else {
            leaseState.invalidate()
            callbackGate.invalidate()
            invalidateDelivery()
            clearInput()
        }
        emitState("terminalAbandoned", errorCode = errorCode, leaseId = lease, owner = owner)
    }

    private fun rollbackPrepare() {
        callbackGate.invalidate()
        try { deinitAndUnbind() } catch (error: VoiceCaptureException) {
            Log.e(VOICE_TAG, "prepare rollback deinit failed", error)
        }
        if (!ProcessTerminalGate.isTerminal) {
            try { releaseSsp() } catch (error: VoiceCaptureException) {
                Log.e(VOICE_TAG, "prepare rollback SSP release failed", error)
            }
        }
    }

    private fun checkNotDisposed() {
        if (ProcessTerminalGate.isTerminal) {
            throw VoiceCaptureException("TERMINAL_ABANDONED", "Vendor operation was abandoned: ${ProcessTerminalGate.reason}")
        }
        if (disposed) throw VoiceCaptureException("DISPOSED", "Native voice capture is detached")
    }
}

private class DiagnosticWavFile(
    private val file: File,
    private val channels: Int,
) {
    private val output: RandomAccessFile
    private var pcmBytes = 0
    private var bytesSinceHeaderUpdate = 0

    val path: String get() = file.absolutePath

    init {
        file.parentFile?.mkdirs()
        output = RandomAccessFile(file, "rw")
        output.setLength(0)
        output.write(wavHeader(0))
        output.fd.sync()
    }

    fun write(pcm: ByteArray) {
        output.write(pcm)
        pcmBytes += pcm.size
        bytesSinceHeaderUpdate += pcm.size
        if (bytesSinceHeaderUpdate < 32_000) return

        bytesSinceHeaderUpdate = 0
        updateHeader()
    }

    fun close() {
        updateHeader()
        output.close()
    }

    private fun updateHeader() {
        val end = output.filePointer
        output.seek(0)
        output.write(wavHeader(pcmBytes))
        output.seek(end)
        output.fd.sync()
    }

    private fun wavHeader(pcmSize: Int): ByteArray =
        ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray())
            putInt(36 + pcmSize)
            put("WAVE".toByteArray())
            put("fmt ".toByteArray())
            putInt(16)
            putShort(1.toShort())
            putShort(channels.toShort())
            putInt(16_000)
            putInt(16_000 * channels * 2)
            putShort((channels * 2).toShort())
            putShort(16.toShort())
            put("data".toByteArray())
            putInt(pcmSize)
        }.array()
}

private data class CaptureInput(
    val bytes: ByteArray,
    val callbackGeneration: Long,
    val revision: Long,
    val elapsedRealtimeNanos: Long,
    val capturedAtEpochMicros: Long,
)

private data class InputTimestampSpan(
    var remainingBytes: Int,
    val elapsedRealtimeNanos: Long,
    val capturedAtEpochMicros: Long,
)

/** Fixed-size byte queue for fragmented UAC4 callbacks. */
private class VoiceCaptureException(val code: String, override val message: String) : RuntimeException(message)
