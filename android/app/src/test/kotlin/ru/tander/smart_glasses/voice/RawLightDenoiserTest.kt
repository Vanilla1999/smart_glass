package ru.tander.smart_glasses.voice

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RawLightDenoiserTest {
    @Test
    fun `produces mono frame from channels two three and four`() {
        val denoiser = RawLightDenoiser()
        val output = ByteArray(RawLightDenoiser.OUTPUT_FRAME_BYTES)

        repeat(4) {
            val input = frame(channel1 = 30_000, channel234 = 0)
            repeat(256) { index ->
                val sample = if ((index / 4) % 2 == 0) 4_000 else -4_000
                for (channel in 1..3) writeSample(input, index, channel, sample)
            }
            denoiser.process(input, output)
        }

        assertTrue(rms(output) > 500.0)
        assertTrue(rms(output) < 5_000.0)
    }

    @Test
    fun `ignores channel one`() {
        val denoiser = RawLightDenoiser()
        val output = ByteArray(RawLightDenoiser.OUTPUT_FRAME_BYTES)

        repeat(4) {
            denoiser.process(frame(channel1 = 30_000, channel234 = 0), output)
        }

        assertEquals(0.0, rms(output), 1.0)
    }

    @Test
    fun `high pass suppresses low frequency more than speech frequency`() {
        val low = processedRms(40.0)
        val speech = processedRms(1_000.0)

        assertTrue("low=$low speech=$speech", speech > low * 3.0)
    }

    private fun processedRms(frequency: Double): Double {
        val denoiser = RawLightDenoiser()
        val output = ByteArray(RawLightDenoiser.OUTPUT_FRAME_BYTES)
        var sampleOffset = 0
        repeat(12) {
            val input = ByteArray(RawLightDenoiser.INPUT_FRAME_BYTES)
            repeat(256) { index ->
                val sample = (8_000 * sin(2.0 * PI * frequency * (sampleOffset + index) / 16_000)).toInt()
                for (channel in 1..3) writeSample(input, index, channel, sample)
            }
            sampleOffset += 256
            denoiser.process(input, output)
        }
        return rms(output)
    }

    private fun frame(channel1: Int, channel234: Int): ByteArray =
        ByteArray(RawLightDenoiser.INPUT_FRAME_BYTES).also { bytes ->
            repeat(256) { index ->
                writeSample(bytes, index, 0, channel1)
                for (channel in 1..3) writeSample(bytes, index, channel, channel234)
            }
        }

    private fun writeSample(bytes: ByteArray, index: Int, channel: Int, sample: Int) {
        val offset = (index * 4 + channel) * 2
        bytes[offset] = sample.toByte()
        bytes[offset + 1] = (sample shr 8).toByte()
    }

    private fun rms(bytes: ByteArray): Double {
        var sum = 0.0
        repeat(bytes.size / 2) { index ->
            val offset = index * 2
            val sample = ((bytes[offset + 1].toInt() shl 8) or
                (bytes[offset].toInt() and 0xff)).toShort().toInt()
            sum += sample.toDouble() * sample
        }
        return sqrt(sum / (bytes.size / 2))
    }
}
