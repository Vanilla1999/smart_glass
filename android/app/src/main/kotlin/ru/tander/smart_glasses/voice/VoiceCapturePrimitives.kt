package ru.tander.smart_glasses.voice

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicReference

data class DeliveryKey(val revision: Long, val leaseId: Long, val sequence: Long)

data class PcmAcknowledgement(val status: Int, val leaseId: Long, val sequence: Long)

data class CaptureLease(val owner: String, val leaseId: Long, val revision: Long)

class CaptureLeaseState {
    @Volatile var active: CaptureLease? = null
        private set
    @Volatile var revision: Long = 0
        private set
    var lastCompleted: CaptureLease? = null
        private set
    private var nextLeaseId = 1L

    fun begin(owner: String): CaptureLease {
        check(active == null) { "CAPTURE_BUSY" }
        val lease = CaptureLease(owner, nextLeaseId++, ++revision)
        active = lease
        return lease
    }

    fun complete(expectedOwner: String, expectedLeaseId: Long): CaptureLease {
        val lease = active ?: error("STALE_LEASE")
        check(lease.leaseId == expectedLeaseId) { "STALE_LEASE" }
        check(lease.owner == expectedOwner) { "OWNER_MISMATCH" }
        active = null
        lastCompleted = lease
        revision++
        return lease
    }

    fun invalidate(): CaptureLease? {
        val lease = active
        if (lease != null) lastCompleted = lease
        active = null
        revision++
        return lease
    }
}

object PcmAckProtocol {
    const val BYTES = 24
    const val VERSION = 1
    const val ACCEPTED = 0
    const val STALE_LEASE = 1
    const val MALFORMED_PACKET = 2
    const val INVALID_PACKET = 3
    const val CONSUMER_REJECTED = 4
    const val CONSUMER_FAILURE = 5
    private val VALID_STATUSES = ACCEPTED..CONSUMER_FAILURE

    fun decode(reply: ByteBuffer?): PcmAcknowledgement? {
        if (reply == null || reply.remaining() != BYTES) return null
        val view = reply.slice().order(ByteOrder.BIG_ENDIAN)
        if (view.int != VERSION) return null
        val status = view.int
        if (status !in VALID_STATUSES) return null
        return PcmAcknowledgement(status, view.long, view.long)
    }

    fun failureCode(status: Int): String? = when (status) {
        ACCEPTED -> null
        CONSUMER_REJECTED -> "RECOGNITION_BACKLOG"
        CONSUMER_FAILURE -> "PCM_CONSUMER_FAILED"
        STALE_LEASE, MALFORMED_PACKET, INVALID_PACKET -> "INVALID_PCM_FRAME"
        else -> "PCM_ACK_PROTOCOL_ERROR"
    }
}

class PendingDeliveryState {
    var pending: DeliveryKey? = null
        private set

    fun begin(key: DeliveryKey): Boolean {
        if (pending != null) return false
        pending = key
        return true
    }

    fun settle(key: DeliveryKey): Boolean {
        if (pending != key) return false
        pending = null
        return true
    }

    fun invalidate(): DeliveryKey? = pending.also { pending = null }
}

class ByteBudget(private val capacity: Int) {
    var used: Int = 0
        private set

    fun acquire(bytes: Int): Boolean {
        if (bytes <= 0 || bytes > capacity - used) return false
        used += bytes
        return true
    }

    fun release(bytes: Int) {
        require(bytes in 0..used)
        used -= bytes
    }

    fun clear() { used = 0 }
}

class GenerationGate {
    @Volatile var generation: Long = 0
        private set

    fun next(): Long = ++generation
    fun accepts(candidate: Long): Boolean = candidate == generation
    fun invalidate() { generation++ }
}

class DrainSignal {
    private var scheduled = false

    fun request(force: Boolean = false): Boolean {
        if (force) scheduled = false
        if (scheduled) return false
        scheduled = true
        return true
    }

    fun idle() { scheduled = false }
}

class TerminalGate {
    var reason: String? = null
        private set

    val isTerminal: Boolean get() = reason != null

    fun abandon(errorCode: String): Boolean {
        if (reason != null) return false
        reason = errorCode
        return true
    }

    fun check() {
        check(!isTerminal) { "TERMINAL_ABANDONED" }
    }
}

class LateInitCleanupGate {
    private val abandoned = java.util.concurrent.atomic.AtomicBoolean(false)
    private val cleanupClaimed = java.util.concurrent.atomic.AtomicBoolean(false)

    fun abandon() { abandoned.set(true) }

    fun claimCleanup(): Boolean = abandoned.get() && cleanupClaimed.compareAndSet(false, true)
}

class PcmStreamingGate(private val requiredPackets: Int = 3) {
    var acceptedPackets: Int = 0
        private set

    val isStreaming: Boolean get() = acceptedPackets >= requiredPackets

    fun acceptValidPacket(): Boolean {
        acceptedPackets++
        return acceptedPackets == requiredPackets
    }

    fun reset() { acceptedPackets = 0 }
}

object ProcessTerminalGate {
    private val terminalReason = AtomicReference<String?>(null)

    val reason: String? get() = terminalReason.get()
    val isTerminal: Boolean get() = reason != null

    fun abandon(errorCode: String): Boolean = terminalReason.compareAndSet(null, errorCode)
}
