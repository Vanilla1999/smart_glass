package ru.tander.smart_glasses.voice

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceCapturePrimitivesTest {
    @Test fun ackRequiresExactProtocolAndIdentityFields() {
        val buffer = ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN)
            .putInt(1).putInt(0).putLong(7).putLong(9).flip() as ByteBuffer
        assertEquals(PcmAcknowledgement(0, 7, 9), PcmAckProtocol.decode(buffer))
        assertNull(PcmAckProtocol.decode(ByteBuffer.allocate(23)))
        assertNull(PcmAckProtocol.decode(ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN)
            .putInt(2).putInt(0).putLong(7).putLong(9).flip() as ByteBuffer))
    }

    @Test fun completionMustMatchRevisionLeaseAndSequence() {
        val state = PendingDeliveryState()
        val current = DeliveryKey(3, 7, 9)
        assertTrue(state.begin(current))
        assertFalse(state.settle(current.copy(revision = 2)))
        assertFalse(state.settle(current.copy(leaseId = 8)))
        assertFalse(state.settle(current.copy(sequence = 10)))
        assertTrue(state.settle(current))
    }

    @Test fun inputBudgetIsEightFramesByBytes() {
        val budget = ByteBudget(8 * 2048)
        assertTrue(budget.acquire(7 * 2048))
        assertTrue(budget.acquire(2048))
        assertFalse(budget.acquire(1))
        budget.release(4096)
        assertTrue(budget.acquire(4096))
    }

    @Test fun inputBudgetAcceptsEightObservedVendorPackets() {
        val budget = ByteBudget(8 * 32 * 1024)
        repeat(8) { assertTrue(budget.acquire(32 * 1024)) }
        assertFalse(budget.acquire(1))
    }

    @Test fun staleGenerationsAreRejected() {
        val gate = GenerationGate()
        val first = gate.next()
        val second = gate.next()
        assertFalse(gate.accepts(first))
        assertTrue(gate.accepts(second))
        gate.invalidate()
        assertFalse(gate.accepts(second))
    }

    @Test fun acknowledgementCanForceDrainWakeupAfterBlockedDrain() {
        val signal = DrainSignal()
        assertTrue(signal.request())
        assertFalse(signal.request())
        assertTrue(signal.request(force = true))
    }

    @Test fun terminalGateRetainsFirstTimeoutAndRejectsFutureWork() {
        val gate = TerminalGate()
        assertTrue(gate.abandon("UAC4_START_TIMEOUT"))
        assertFalse(gate.abandon("UAC4_STOP_TIMEOUT"))
        assertEquals("UAC4_START_TIMEOUT", gate.reason)
        try {
            gate.check()
            throw AssertionError("terminal gate accepted work")
        } catch (error: IllegalStateException) {
            assertEquals("TERMINAL_ABANDONED", error.message)
        }
    }

    @Test fun rapidStopStartCreatesDistinctLeaseAndRevision() {
        val state = CaptureLeaseState()
        val first = state.begin("wearRecognition")
        state.complete(first.owner, first.leaseId)
        val second = state.begin("wearRecognition")

        assertTrue(second.leaseId > first.leaseId)
        assertTrue(second.revision > first.revision)
        assertEquals(second, state.active)
    }

    @Test fun staleStopCannotCompleteAReplacementLease() {
        val state = CaptureLeaseState()
        val first = state.begin("wearRecognition")
        state.complete(first.owner, first.leaseId)
        val second = state.begin("voiceMemo")

        try {
            state.complete(first.owner, first.leaseId)
            throw AssertionError("stale stop completed replacement lease")
        } catch (error: IllegalStateException) {
            assertEquals("STALE_LEASE", error.message)
        }
        assertEquals(second, state.active)
    }

    @Test fun secondOwnerCannotReplaceAnActiveLease() {
        val state = CaptureLeaseState()
        val active = state.begin("wearRecognition")

        try {
            state.begin("voiceMemo")
            throw AssertionError("second owner replaced active lease")
        } catch (error: IllegalStateException) {
            assertEquals("CAPTURE_BUSY", error.message)
        }
        assertEquals(active, state.active)
    }

    @Test fun binderAndCallbackGenerationsRejectLateSignalsAfterRestart() {
        val binder = GenerationGate()
        val callback = GenerationGate()
        val oldBinder = binder.next()
        val oldCallback = callback.next()
        binder.invalidate()
        callback.invalidate()
        val newBinder = binder.next()
        val newCallback = callback.next()

        assertFalse(binder.accepts(oldBinder))
        assertFalse(callback.accepts(oldCallback))
        assertTrue(binder.accepts(newBinder))
        assertTrue(callback.accepts(newCallback))
    }

    @Test fun detachInvalidatesPendingDeliveryWithoutSettlingNewEpoch() {
        val state = PendingDeliveryState()
        val detached = DeliveryKey(revision = 1, leaseId = 1, sequence = 0)
        assertTrue(state.begin(detached))
        assertEquals(detached, state.invalidate())

        val attached = DeliveryKey(revision = 3, leaseId = 2, sequence = 0)
        assertTrue(state.begin(attached))
        assertFalse(state.settle(detached))
        assertEquals(attached, state.pending)
    }

    @Test fun lateInitCleanupCanBeClaimedExactlyOnceAfterTimeout() {
        val gate = LateInitCleanupGate()
        assertFalse(gate.claimCleanup())
        gate.abandon()
        assertTrue(gate.claimCleanup())
        assertFalse(gate.claimCleanup())
    }

    @Test fun threeValidPacketsAreRequiredForStreaming() {
        val gate = PcmStreamingGate()
        assertFalse(gate.acceptValidPacket())
        assertFalse(gate.acceptValidPacket())
        assertTrue(gate.acceptValidPacket())
        assertTrue(gate.isStreaming)
        gate.reset()
        assertFalse(gate.isStreaming)
    }
}
