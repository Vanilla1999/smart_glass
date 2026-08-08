package ru.tander.smart_glasses.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AlignedFourChannelMixerTest {
    @Test
    fun `aligns measured near mouth channel arrivals`() {
        val mixer = AlignedFourChannelMixer()
        val input = ByteArray(16 * 4 * 2)
        val output = DoubleArray(16)
        val amplitude = 12_000

        writeSample(input, sampleIndex = 4, channel = 0, sample = amplitude)
        writeSample(input, sampleIndex = 7, channel = 1, sample = amplitude)
        writeSample(input, sampleIndex = 5, channel = 2, sample = amplitude)
        writeSample(input, sampleIndex = 5, channel = 3, sample = amplitude)

        assertEquals(16, mixer.mix(input, output))
        assertEquals(amplitude / 32768.0, output[7], 1e-12)
        output.forEachIndexed { index, sample ->
            if (index != 7) assertEquals("index=$index", 0.0, sample, 1e-12)
        }
    }

    @Test
    fun `preserves delayed history across packet boundaries`() {
        val mixer = AlignedFourChannelMixer()
        val first = ByteArray(4 * 4 * 2)
        val second = ByteArray(4 * 4 * 2)
        val firstOutput = DoubleArray(4)
        val secondOutput = DoubleArray(4)

        writeSample(first, sampleIndex = 3, channel = 0, sample = 16_000)
        mixer.mix(first, firstOutput)
        mixer.mix(second, secondOutput)

        assertTrue(firstOutput.all { it == 0.0 })
        assertEquals(16_000 / 4.0 / 32768.0, secondOutput[2], 1e-12)
    }

    @Test
    fun `reset clears delayed channel history`() {
        val mixer = AlignedFourChannelMixer()
        val input = ByteArray(4 * 4 * 2)
        val output = DoubleArray(4)

        writeSample(input, sampleIndex = 3, channel = 0, sample = 16_000)
        mixer.mix(input, output)
        mixer.reset()
        output.fill(Double.NaN)
        mixer.mix(ByteArray(input.size), output)

        assertTrue(output.all { it == 0.0 })
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rejects incomplete interleaved sample frame`() {
        AlignedFourChannelMixer().mix(ByteArray(7), DoubleArray(1))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rejects negative channel delay`() {
        AlignedFourChannelMixer(intArrayOf(3, 0, -1, 2))
    }

    private fun writeSample(bytes: ByteArray, sampleIndex: Int, channel: Int, sample: Int) {
        val offset = (sampleIndex * 4 + channel) * 2
        bytes[offset] = sample.toByte()
        bytes[offset + 1] = (sample shr 8).toByte()
    }
}
