package ru.tander.multi_scanner

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Log
import com.xc.arsdk.ARSdk
import com.xcheng.scanner.BarcodeType
import com.xcheng.scanner.OnCameraFrameDetailListener
import com.xcheng.scanner.ScannerResult
import com.xcheng.scanner.XcBarcodeScanner
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class DirectMovfastGlassesScanner : CoroutineScope, ScannerResult {
    override val coroutineContext = Dispatchers.Main

    private var arSdk: ARSdk? = null
    private var flashlightState: Int = 0
    @Volatile private var initialized = false
    private var photoCapture: GlassesPhotoCapture? = null
    var onBarcode: ((String) -> Unit)? = null

    suspend fun init(context: Context): Boolean {
        if (initialized) {
            Log.i("DirectGlass", "init skipped: already initialized")
            return true
        }
        Log.i("DirectGlass", "init begin")
        XcBarcodeScanner.init(context.applicationContext, this)
        delay(500)
        photoCapture = GlassesPhotoCapture(context.applicationContext)
        ARSdk.initialize(context.applicationContext)
        arSdk = ARSdk.getInstance()
        Log.i("DirectGlass", "ARSdk.getInstance()=$arSdk")
        arSdk!!.connect()
        Log.i("DirectGlass", "ARSdk.connect() called, waiting for connection...")
        // Wait for service binding (up to 10 seconds)
        var waited = 0
        while (arSdk?.isConnected != true && waited < 10_000) {
            delay(200)
            waited += 200
        }
        val connected = arSdk?.isConnected == true
        Log.i("DirectGlass", "ARSdk connected=$connected waited=${waited}ms isGlassesConnected=${arSdk?.isGlassesConnected}")
        if (!connected) {
            Log.e("DirectGlass", "ARSdk failed to connect")
            return false
        }
        initialized = true
        Log.i("DirectGlass", "init end ok")
        return true
    }

    fun setFlashlight(state: Int) {
        flashlightState = state
        val sdk = arSdk
        if (sdk == null) {
            Log.e("DirectGlass", "setFlashlight($state): ARSdk=NULL")
            return
        }
        Log.i("DirectGlass", "setFlashlight($state): calling ARSdk")
        val start = System.currentTimeMillis()
        try {
            sdk.setFlashlight(state)
            val elapsed = System.currentTimeMillis() - start
            Log.i("DirectGlass", "setFlashlight($state): ARSdk returned ok in ${elapsed}ms")
        } catch (e: Exception) {
            val elapsed = System.currentTimeMillis() - start
            Log.e("DirectGlass", "setFlashlight($state): ARSdk FAILED in ${elapsed}ms", e)
            throw e
        }
    }

    fun getFlashlightState(): Int {
        Log.i("DirectGlass", "getFlashlightState: cached=$flashlightState arSdk=${arSdk != null}")
        return flashlightState
    }

    fun isGlassesConnected(): Boolean = arSdk?.isGlassesConnected ?: false

    suspend fun takePhoto(ownerPackage: String, context: Context): File {
        return photoCapture?.takePhoto(ownerPackage)
            ?: throw IllegalStateException("Photo capture not initialized. Call init() first.")
    }

    fun release(context: Context) {
        photoCapture?.close()
        photoCapture = null
        try { XcBarcodeScanner.deInit(context.applicationContext) } catch (e: Exception) {
            Log.e("DirectGlass", "deInit failed", e)
        }
        initialized = false
    }

    override fun onResult(barcodeStr: String) {
        Log.i("DirectGlass", "barcode: $barcodeStr")
        onBarcode?.invoke(barcodeStr)
    }
}

class GlassesPhotoCapture(
    context: Context,
    private val timeoutMillis: Long = 5_000L,
) : Closeable {
    private val appContext = context.applicationContext
    private val captureMutex = Mutex()
    private val activeAttempt = AtomicReference<CaptureAttempt?>()
    private val closed = AtomicBoolean(false)

    suspend fun takePhoto(ownerPackage: String): File {
        check(!closed.get()) { "Photo capture is closed" }
        if (!captureMutex.tryLock()) throw IllegalStateException("Photo capture in progress")
        try {
            check(XcBarcodeScanner.isServiceBound()) { "Scanner service not bound" }
            val frame = withContext(Dispatchers.IO) {
                try { withTimeout(timeoutMillis) { awaitFrame() } }
                catch (e: TimeoutCancellationException) { throw IOException("Camera frame timeout", e) }
            }
            val outputFile = withContext(Dispatchers.IO) { createOutputFile(ownerPackage) }
            try {
                withContext(Dispatchers.IO) { saveFrame(outputFile, frame.bytes, frame.width, frame.height, frame.format) }
                if (closed.get()) throw IllegalStateException("Photo capture closed")
                return outputFile
            } catch (e: Throwable) {
                withContext(NonCancellable + Dispatchers.IO) { outputFile.delete() }
                throw e
            }
        } finally { captureMutex.unlock() }
    }

    private suspend fun awaitFrame(): CameraFrame = suspendCancellableCoroutine { cont ->
        val attempt = CaptureAttempt(cont)
        activeAttempt.compareAndSet(null, attempt)
        cont.invokeOnCancellation {
            if (attempt.finished.compareAndSet(false, true)) {
                activeAttempt.compareAndSet(attempt, null)
                unregisterFrameListener()
            }
        }
        val listener = object : OnCameraFrameDetailListener {
            override fun onFrame(bytes: ByteArray, width: Int, height: Int, timestamp: Long, format: Int, snTimeStamp: String?) {
                if (!attempt.finished.compareAndSet(false, true)) return
                val frame = CameraFrame(bytes.copyOf(), width, height, format)
                activeAttempt.compareAndSet(attempt, null)
                cont.resume(frame)
            }
            override fun onError(code: Int, message: String?) {
                failAttempt(attempt, IOException("Camera error $code: ${message.orEmpty()}"))
            }
        }
        try {
            XcBarcodeScanner.setOnCameraFrameDetailListener(listener)
            if (!XcBarcodeScanner.isLoopScanRunning()) XcBarcodeScanner.startScan()
        } catch (e: Exception) { failAttempt(attempt, e) }
    }

    private fun createOutputFile(ownerPackage: String): File {
        val dir = File(File(appContext.filesDir, "glasses"), ownerPackage)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("Failed to create dir: ${dir.absolutePath}")
        return File(dir, "glasses_photo_${UUID.randomUUID()}.jpg")
    }

    private fun saveFrame(outputFile: File, bytes: ByteArray, width: Int, height: Int, format: Int) {
        outputFile.outputStream().use { it.write(encodeToJpeg(bytes, width, height, format)) }
    }

    private fun failAttempt(attempt: CaptureAttempt, error: Throwable) {
        if (!attempt.finished.compareAndSet(false, true)) return
        activeAttempt.compareAndSet(attempt, null)
        unregisterFrameListener()
        attempt.continuation.resumeWithException(error)
    }

    private fun unregisterFrameListener() {
        try { XcBarcodeScanner.setOnCameraFrameDetailListener(null) } catch (_: Exception) {}
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        activeAttempt.getAndSet(null)?.let { if (it.finished.compareAndSet(false, true)) it.continuation.cancel() }
        unregisterFrameListener()
    }

    private data class CameraFrame(val bytes: ByteArray, val width: Int, val height: Int, val format: Int)
    private class CaptureAttempt(val continuation: CancellableContinuation<CameraFrame>) { val finished = AtomicBoolean(false) }
}

private fun encodeToJpeg(bytes: ByteArray, width: Int, height: Int, format: Int): ByteArray {
    if (format == ImageFormat.JPEG) return bytes
    val nv21 = when (format) {
        ImageFormat.NV21 -> bytes
        ImageFormat.YUV_420_888 -> bytes.copyOf(width * height * 3 / 2)
        ImageFormat.YUY2 -> bytes
        else -> throw IllegalArgumentException("Unsupported format: $format")
    }
    val jpegFormat = if (format == ImageFormat.YUY2) ImageFormat.YUY2 else ImageFormat.NV21
    return ByteArrayOutputStream().use { out ->
        YuvImage(nv21, jpegFormat, width, height, null).compressToJpeg(Rect(0, 0, width, height), 90, out)
        out.toByteArray()
    }
}
