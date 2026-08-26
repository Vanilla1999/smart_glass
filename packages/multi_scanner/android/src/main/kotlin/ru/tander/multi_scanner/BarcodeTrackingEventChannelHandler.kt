package ru.tander.multi_scanner

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import ru.tander.aidl.BarcodeTrackingParcel

class BarcodeTrackingEventChannelHandler {
    private lateinit var eventChannel: EventChannel
    private var event: EventChannel.EventSink? = null

    fun startListening(messenger: BinaryMessenger) {
        eventChannel = EventChannel(
            messenger,
            "tander/multi_scanner_plugin/event_barcode_tracking",
        )
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                event = events
            }

            override fun onCancel(arguments: Any?) {
                event = null
            }
        })
    }

    fun emit(value: BarcodeTrackingParcel) {
        event?.success(
            mapOf(
                "contractVersion" to value.contractVersion,
                "sequence" to value.sequence,
                "candidateId" to value.candidateId,
                "capturedAtElapsedRealtimeNanos" to value.capturedAtElapsedRealtimeNanos,
                "detectedAtElapsedRealtimeNanos" to value.detectedAtElapsedRealtimeNanos,
                "phase" to value.phase,
                "frameWidth" to value.frameWidth,
                "frameHeight" to value.frameHeight,
                "rotationDegrees" to value.rotationDegrees,
                "mirrored" to value.mirrored,
                "left" to value.left,
                "top" to value.top,
                "right" to value.right,
                "bottom" to value.bottom,
            ),
        )
    }

    fun stopListening() {
        event = null
        eventChannel.setStreamHandler(null)
    }
}
