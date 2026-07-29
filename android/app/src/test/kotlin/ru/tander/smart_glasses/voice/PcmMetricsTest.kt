package ru.tander.smart_glasses.voice

import org.junit.Assert.assertEquals
import org.junit.Test

class PcmMetricsTest {
    @Test
    fun assignsInterleavedSamplesToFourChannels() {
        val input = byteArrayOf(
            1, 0, 2, 0, 3, 0, 4, 0,
            1, 0, 2, 0, 3, 0, 4, 0,
        )
        val metrics = PcmMetrics.interleavedPcm16Le(input, 4)
        assertEquals(1.0 / 32768.0, metrics[0].peak, 0.0000001)
        assertEquals(2.0 / 32768.0, metrics[1].peak, 0.0000001)
        assertEquals(3.0 / 32768.0, metrics[2].peak, 0.0000001)
        assertEquals(4.0 / 32768.0, metrics[3].peak, 0.0000001)
    }
}
