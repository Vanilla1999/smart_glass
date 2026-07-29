package ru.tander.smart_glasses.voice

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmRingBufferTest {
    @Test
    fun preservesFragmentedFramesAndRemainder() {
        val ring = PcmRingBuffer(4096)
        val frame = ByteArray(2048) { (it % 251).toByte() }
        assertTrue(ring.append(frame.copyOfRange(0, 511)))
        assertTrue(ring.append(frame.copyOfRange(511, frame.size)))
        val output = ByteArray(2048)
        assertTrue(ring.readFrame(output))
        assertArrayEquals(frame, output)
        assertFalse(ring.readFrame(output))
    }

    @Test
    fun rejectsCapacityOverflow() {
        val ring = PcmRingBuffer(8)
        assertTrue(ring.append(ByteArray(8)))
        assertFalse(ring.append(byteArrayOf(1)))
    }

    @Test
    fun drainsAllSixteenSspFramesFromVendorPacket() {
        val ring = PcmRingBuffer(2 * 32 * 1024)
        assertTrue(ring.append(ByteArray(32 * 1024)))

        val frame = ByteArray(2048)
        var frames = 0
        while (ring.readFrame(frame)) frames++

        assertEquals(16, frames)
        assertEquals(0, ring.size)
    }
}
