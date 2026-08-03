package ru.tander.multi_scanner

import android.annotation.SuppressLint
import android.app.Activity
import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.annotation.NonNull
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleCoroutineScope
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.OnLifecycleEvent
import androidx.lifecycle.coroutineScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.gson.GsonBuilder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import ru.tander.aidl.BluetoothDeviceParcel
import ru.tander.viScanner.WakeUpHelper
import ru.tander.viScanner.ViBarcodeHelper
import ru.tander.viScanner.ViBluetoothScannerApi
import ru.tander.viScanner.ViScanner
import ru.tander.viScanner.scanners.BarcodeSettingsConfig
import ru.tander.viScanner.bluetooth.ViBluetoothScanner
import ru.tander.viScanner.bluetooth.adapters.BTDevice
import ru.tander.viScanner.cameraScanner.ViCameraScanner
import java.lang.Exception
import kotlin.coroutines.CoroutineContext


/** AppUsagePlugin */
class MultiScannerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, CoroutineScope, EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private var eventChannel: EventChannel? = null
    private var eventSinkServiceConnections: EventSink? = null
    private var eventScannerDisabled: EventChannel? = null
    private var eventSinkScannerDisabled: EventSink? = null
    private var activity: Activity? = null
    private var lifecycle: Lifecycle? = null
    private lateinit var eventHandler: EventChannelHandler
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var componentActivity: ComponentActivity? = null
    private var viCameraScanner: ViCameraScanner? = null
    private val pluginJob = SupervisorJob()
    private val scannerLifecycleMutex = Mutex()
    private val lifecycleScope: LifecycleCoroutineScope?
        get() = lifecycle?.coroutineScope
    private val onBtFound = "onBtFound"
    private val onBtBound = "onBtBound"
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger, "tander/multi_scanner_plugin/channel"
        )
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "tander/multi_scanner_plugin/eventSinkServiceConnections")
        eventChannel!!.setStreamHandler(this)
        eventScannerDisabled = EventChannel(flutterPluginBinding.binaryMessenger, "tander/multi_scanner_plugin/event_scanner_disabled")
        eventScannerDisabled!!.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventSink?) {
                eventSinkScannerDisabled = events
            }
            override fun onCancel(arguments: Any?) {
                eventSinkScannerDisabled = null
            }
        })
    }

    private var viBluetooth: ViBluetoothScannerApi? = null
    private var wearPrepared = false
    private val observer = object : LifecycleObserver {

        @OnLifecycleEvent(Lifecycle.Event.ON_START)
        fun onStart() {
            // Handle activity onStart event
        }

        @OnLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        fun onPause() {
            // Wear owns scanner lifecycle explicitly so screen-off does not pause it.
        }

        @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
        fun onStop() {
            // Handle activity onStop event
        }

        @OnLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        fun onDestroy() {
            launch {
                scannerLifecycleMutex.withLock {
                    WakeUpHelper().disableTurnOffDeviseOnScanButton()
                    ViScanner.release()
                    wearPrepared = false
                }
            }
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }

            "switchHoneywellLight" -> {
                val flag = call.argument<Boolean>("flag") ?: false
                launch {
                    ViScanner.getAdditionalHoneywell()?.changeFlagLight(flag)
                    result.success(null)
                }
            }

            "getHoneywellLight" -> {
                launch {
                    result.success((ViScanner.getAdditionalHoneywell()?.getFlagLight()))
                }
            }

            "setFlashlight" -> {
                val state = call.argument<Int>("state") ?: 0
                launch {
                    try {
                        ViScanner.getAdditionalMovfastGlass()?.setFlashlight(state)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "getFlashlightState" -> {
                launch {
                    try {
                        result.success(ViScanner.getAdditionalMovfastGlass()?.getFlashlightState() ?: 0)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "takePhoto" -> {
                launch {
                    try {
                        val glasses = ViScanner.getAdditionalMovfastGlass()
                            ?: throw UnsupportedOperationException(
                                "Photo capture is supported only on Movfast glasses"
                            )

                        val uri = glasses.takePhoto()
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error(
                            "PHOTO_CAPTURE_FAILED",
                            e.message ?: "Photo capture failed",
                            null,
                        )
                    }
                }
            }

            "deletePhoto" -> {
                val contentUri = call.argument<String>("uri")

                if (contentUri.isNullOrBlank()) {
                    result.error(
                        "INVALID_PHOTO_URI",
                        "Photo URI is required",
                        null,
                    )
                    return
                }

                launch {
                    try {
                        val glasses = ViScanner.getAdditionalMovfastGlass()
                            ?: throw UnsupportedOperationException(
                                "Photo deletion is supported only on Movfast glasses"
                            )

                        glasses.deletePhoto(Uri.parse(contentUri))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error(
                            "PHOTO_DELETE_FAILED",
                            e.message ?: "Photo deletion failed",
                            null,
                        )
                    }
                }
            }

            "isServiceConnected" -> {
                launch {
                    val isConnected = try {
                        ViScanner.isInit() && ViScanner.isServiceConnectedStateFlow.value
                    } catch (e: Exception) {
                        false
                    }
                    result.success(isConnected)
                }
            }

            "setUserScanSettings" -> {
                launch {
                    val settings = call.argument<String>("settings")
                    ViBarcodeHelper.setConfig(
                        GsonBuilder().create().fromJson(
                            settings, BarcodeSettingsConfig::class.java
                        )
                    )
                    result.success(null)
                }
            }

            "changeRhkHoneywell" -> {
                launch {
                    val flag = call.argument<Boolean>("flag") ?: false
                    ViScanner.getAdditionalHoneywell()?.changeIsRhk(flag)
                    result.success(null)
                }
            }

            "setDefaultSettings" -> {
                launch {
                    try {
                        ViBarcodeHelper.setDefaultSettings()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "setRecomendedSettings" -> {
                launch {
                    try {
                        ViBarcodeHelper.setRecomendedSettings()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "goToCOMMode" -> {
                launch {
                    try {
                        ViScanner.getAdditionalMertechPCH()?.goToCOMMode()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "goToHIDMode" -> {
                launch {
                    try {
                        ViScanner.getAdditionalMertechPCH()?.goToHIDMode()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "init" -> {
                launch {
                    try {
                        scannerLifecycleMutex.withLock {
                            Log.d("viScanner", "init")
                            if (!ViScanner.isInit()) {
                                lifecycleScope?.launch { // 1
                                    lifecycle?.repeatOnLifecycle(Lifecycle.State.STARTED) {
                                        launch {
                                            ViScanner.isServiceConnectedStateFlow.collect {
                                                eventSinkServiceConnections?.success(it);
                                            }
                                        }
                                    }
                                }
                                ViScanner.init(activity!!, registry = componentActivity!!.activityResultRegistry)
                                if (!ViScanner.isInitScanner()) {
                                    ViScanner.initScanner()
                                }
                                ViScanner.prepare()
                                wearPrepared = true
                                viBluetooth = ViScanner.getViBluetoothScannerApi()
                            }
                            ViScanner.registerBarcodeCallBack {
                                Log.d("barcode", it)
                                sendBroadcast(it, "")
                            }
                            ViScanner.setDisabledScannerListener {
                                Log.d("viScanner", "Disabledddd")
                                eventSinkScannerDisabled?.success(true)
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        Log.d("viScanner", "init Error")
                        result.error("0", e.message, null)
                    }
                }
            }

            "prepareForWear" -> {
                launch {
                    try {
                        scannerLifecycleMutex.withLock {
                            if (!wearPrepared) {
                                ViScanner.prepare()
                                wearPrepared = true
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error(
                            "SCANNER_PREPARE_FAILED",
                            e.message ?: "Scanner prepare failed",
                            null,
                        )
                    }
                }
            }

            "pauseForWear" -> {
                launch {
                    try {
                        scannerLifecycleMutex.withLock {
                            if (wearPrepared) {
                                ViScanner.pause()
                                wearPrepared = false
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error(
                            "SCANNER_PAUSE_FAILED",
                            e.message ?: "Scanner pause failed",
                            null,
                        )
                    }
                }
            }

            "wakeUpOnScanButton" -> {
                launch {
                    try {
                        WakeUpHelper().enableTurnOnDeviseOnScanButton()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "scanBarcodeByCamera" -> {
                launch {
                    withContext(Dispatchers.Main) {
                        result.success(viCameraScanner?.scanBarcode())
                    }
                }
            }

            "startDiscovery" -> {
                viBluetooth?.startDiscovery()
                result.success(null)
            }

            "cancelDiscovery" -> {
                viBluetooth?.cancelDiscovery()
                result.success(null)
            }

            "clearBTList" -> {
                viBluetooth?.clearBTList()
                result.success(null)
            }

            "initBluetooth" -> {
                viBluetooth?.initBluetooth()
                registerListeners()
                Log.d("viScanner", "initBluetooth $viBluetooth")
                result.success(null)
            }

            "stopWork" -> {
                viBluetooth?.stopWork()
                result.success(null)
            }

            "startWork" -> {
                viBluetooth?.startWork()
                result.success(null)
            }

            "releaseBluettoth" -> {
                launch {
                    viBluetooth?.release()
                }
                result.success(null)
            }

            "release" -> {
                launch {
                    try {
                        scannerLifecycleMutex.withLock {
                            ViScanner.release()
                            wearPrepared = false
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error(
                            "SCANNER_RELEASE_FAILED",
                            e.message ?: "Scanner release failed",
                            null,
                        )
                    }
                }
            }

            "createBond" -> {
                val deviceName = call.argument<String?>("deviceName")
                val macAdress = call.argument<String?>("macAdress")
                viBluetooth?.createBond(BluetoothDeviceParcel(name = deviceName, macAdress = macAdress, type = null))
                result.success(null)
            }

            "showBluetoothDialog" -> {
                launch {
                    ViScanner.showBluetoothDialog((activity as FragmentActivity).supportFragmentManager)
                }
                result.success(null)
            }

            "connectToBT" -> {
                val deviceName = call.argument<String?>("deviceName")
                val macAdress = call.argument<String?>("macAdress")
                viBluetooth?.connectToBT(BluetoothDeviceParcel(name = deviceName, macAdress = macAdress, type = null))
                result.success(null)
            }

            "removeBound" -> {
                val deviceName = call.argument<String?>("deviceName")
                val macAdress = call.argument<String?>("macAdress")
                viBluetooth?.removeBound(BluetoothDeviceParcel(name = deviceName, macAdress = macAdress, type = null))
                result.success(null)
            }

            "isPCH" -> {
                lifecycleScope?.launch { result.success(ViScanner.isPCH()) }
            }

            "isDefaultHorizontal" -> {
                lifecycleScope?.launch { result.success(ViScanner.isDefaultHorizontal()) }
            }

            "isNotNeedCamera" -> {
                lifecycleScope?.launch { result.success(ViScanner.isNotNeedCamera()) }
            }

            "isNeedBT" -> {
                lifecycleScope?.launch { result.success(ViScanner.isNeedBT()) }
            }

            "disableScanner" -> {
                launch {
                    try {
                        ViScanner.disableScanner()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "enableScanner" -> {
                launch {
                    try {
                        ViScanner.enableScanner()
                        eventSinkScannerDisabled?.success(false)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("0", e.message, null)
                    }
                }
            }

            "needDefaultExpandKeyboard" -> {
                lifecycleScope?.launch { result.success(ViScanner.needDefaultExpandKeyboard()) }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel!!.setStreamHandler(null)
        eventScannerDisabled!!.setStreamHandler(null)
        cancel()
        flutterPluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        componentActivity = activity as ComponentActivity
        lifecycle = (activity as LifecycleOwner).lifecycle
        eventHandler = EventChannelHandler()
        viCameraScanner = ViCameraScanner(activity!!, componentActivity!!.activityResultRegistry)
        eventHandler.startListening(flutterPluginBinding?.binaryMessenger)
        lifecycle?.addObserver(observer)
    }

    @SuppressLint("MissingPermission")
    private fun registerListeners() {
        lifecycleScope?.launch { // 1
            lifecycle?.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viBluetooth?.listFoundStateFlow?.collect {
                        val json: String = GsonBuilder().create()
                            .toJson(BTDevices(it.map { btDevice ->
                                BTDevice(
                                    btDevice.macAdress ?: "",
                                    btDevice.name ?: ""
                                )
                            }))
                        channel.invokeMethod(onBtFound, json)
                    }
                }
                launch {
                    viBluetooth?.listBoundStateFlow?.collect {
                        val json: String = GsonBuilder().create()
                            .toJson(BTDevices(it.map { btDevice ->
                                BTDevice(
                                    btDevice.macAdress ?: "",
                                    btDevice.name ?: ""
                                )
                            }))
                        channel.invokeMethod(onBtBound, json)
                    }
                }
                launch {
                    viBluetooth?.connectedStateFlow?.collect {
                        Log.d("ConnectedDevice", it.toString())
                        if (it == null) {
                            channel.invokeMethod("connectedState", null)
                            return@collect
                        }
                        if (it.isEmpty()) {
                            return@collect
                        }
                        val json: String = GsonBuilder().create()
                            .toJson(
                                BTDevice(
                                    it.first().macAdress ?: "",
                                    it.first().name ?: ""
                                )
                            )
                        channel.invokeMethod("connectedState", json)
                    }
                }
                launch {
                    viBluetooth?.isBoundingDevice?.collect {
                        Log.d("isBounding", it.toString())
                        if (it == null) {
                            channel.invokeMethod("isBoundingDevice", null)
                            return@collect
                        }
                        val json: String = GsonBuilder().create()
                            .toJson(
                                BTDevice(
                                    it.device.macAdress ?: "",
                                    it.device.name ?: ""
                                )
                            )
                        channel.invokeMethod("isBoundingDevice", json)
                    }
                }

                launch {
                    viBluetooth?.battaryStateFlow?.collect {
                        val json: String = GsonBuilder().create()
                            .toJson(BattaryStateList(it.map { btDevice ->
                                BattaryState(
                                    BTDevice(
                                        btDevice.device.macAdress ?: "",
                                        btDevice.device.name ?: ""
                                    ), battary = btDevice.battary
                                )
                            }))
                        channel.invokeMethod("battaryState", json)
                    }
                }
            }
        }
    }

    private fun sendBroadcast(barcode: String, tsd: String) {
        eventHandler.onScanCompite(barcode, tsd)
    }


    override fun onDetachedFromActivityForConfigChanges() {
        lifecycle?.removeObserver(observer)
        activity = null
        componentActivity = null
        lifecycle = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        componentActivity = activity as ComponentActivity
        lifecycle = (activity as LifecycleOwner).lifecycle
        eventHandler = EventChannelHandler()
        viCameraScanner = ViCameraScanner(activity!!, componentActivity!!.activityResultRegistry)
        eventHandler.startListening(flutterPluginBinding?.binaryMessenger)
        registerListeners()
        lifecycle?.addObserver(observer)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
    }

    override val coroutineContext: CoroutineContext
        get() = pluginJob + Dispatchers.Main

    override fun onListen(arguments: Any?, events: EventSink?) {
        this.eventSinkServiceConnections = events
    }

    override fun onCancel(arguments: Any?) {
        eventSinkServiceConnections = null
    }
}
