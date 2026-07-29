package ru.tander.smart_glasses.voice

class PcmRingBuffer(private val capacity: Int) {
    private val bytes = ByteArray(capacity)
    private var read = 0
    private var write = 0
    var size = 0
        private set

    fun append(input: ByteArray): Boolean {
        if (input.size > capacity - size) return false
        for (byte in input) {
            bytes[write] = byte
            write = (write + 1) % capacity
        }
        size += input.size
        return true
    }

    fun readFrame(output: ByteArray): Boolean {
        if (size < output.size) return false
        for (index in output.indices) {
            output[index] = bytes[read]
            read = (read + 1) % capacity
        }
        size -= output.size
        return true
    }

    fun clear() {
        read = 0
        write = 0
        size = 0
    }
}
