package ru.tander.smart_glasses.voice

import kotlin.math.abs
import kotlin.math.sqrt

data class SignalMetrics(val rms: Double, val peak: Double, val clippingRatio: Double)

object PcmMetrics {
    fun interleavedPcm16Le(
        input: ByteArray,
        channels: Int,
        length: Int = input.size,
    ): List<SignalMetrics> {
        require(length in 1..input.size && channels > 0 && length % (channels * 2) == 0)
        val samplesPerChannel = length / 2 / channels
        val sums = DoubleArray(channels)
        val peaks = IntArray(channels)
        val clipped = IntArray(channels)
        var offset = 0
        repeat(samplesPerChannel) {
            repeat(channels) { channel ->
                val sample = ((input[offset + 1].toInt() shl 8) or (input[offset].toInt() and 0xff)).toShort().toInt()
                val magnitude = if (sample == Short.MIN_VALUE.toInt()) 32768 else abs(sample)
                sums[channel] += sample.toDouble() * sample
                if (magnitude > peaks[channel]) peaks[channel] = magnitude
                if (magnitude == 32768 || magnitude == 32767) clipped[channel]++
                offset += 2
            }
        }
        return List(channels) { channel ->
            SignalMetrics(
                rms = sqrt(sums[channel] / samplesPerChannel) / 32768.0,
                peak = peaks[channel] / 32768.0,
                clippingRatio = clipped[channel].toDouble() / samplesPerChannel,
            )
        }
    }
}
