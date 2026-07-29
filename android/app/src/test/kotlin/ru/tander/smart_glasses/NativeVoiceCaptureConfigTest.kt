package ru.tander.smart_glasses

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeVoiceCaptureConfigTest {
    @Test
    fun pcmAckTimeoutAllowsForSlowNativeRecognizerCalls() {
        assertEquals(2_000L, PCM_ACK_TIMEOUT_MILLIS)
    }
}
