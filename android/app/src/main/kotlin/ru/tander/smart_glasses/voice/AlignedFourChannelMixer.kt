package ru.tander.smart_glasses.voice

/**
 * Causally aligns the four UAC4 microphone channels and mixes them to mono.
 *
 * Measurements from the target near-mouth voice showed relative arrivals of
 * [0, +3, +1, +1] samples. A streaming processor cannot move the late channel
 * backwards, so the equivalent causal delays are [3, 0, 2, 2]. The resulting
 * algorithm adds only three samples (0.1875 ms at 16 kHz) of latency.
 */
class AlignedFourChannelMixer(
    channelDelays: IntArray = intArrayOf(3, 0, 2, 2),
) {
    companion object {
        const val CHANNEL_COUNT = 4
        const val BYTES_PER_SAMPLE = 2
        private const val PCM_SCALE = 32768.0
    }

    private val delays = channelDelays.copyOf()
    private val historyLength: Int
    private val history: Array<IntArray>
    private var writeIndex = 0

    init {
        require(delays.size == CHANNEL_COUNT) {
            "Expected $CHANNEL_COUNT channel delays, got ${delays.size}"
        }
        require(delays.all { it >= 0 }) { "Channel delays must be non-negative" }

        historyLength = (delays.maxOrNull() ?: 0) + 1
        history = Array(CHANNEL_COUNT) { IntArray(historyLength) }
    }

    fun reset() {
        history.forEach { it.fill(0) }
        writeIndex = 0
    }

    /**
     * Mixes interleaved signed PCM16 input into normalized mono samples.
     * Returns the number of mono samples written.
     */
    fun mix(input: ByteArray, output: DoubleArray): Int {
        val bytesPerFrame = CHANNEL_COUNT * BYTES_PER_SAMPLE
        require(input.size % bytesPerFrame == 0) {
            "Input size ${input.size} is not a whole four-channel PCM16 frame"
        }

        val sampleCount = input.size / bytesPerFrame
        require(output.size >= sampleCount) {
            "Output has ${output.size} samples, requires at least $sampleCount"
        }

        repeat(sampleCount) { sampleIndex ->
            for (channel in 0 until CHANNEL_COUNT) {
                history[channel][writeIndex] = readPcm16(input, sampleIndex, channel)
            }

            var mixed = 0.0
            for (channel in 0 until CHANNEL_COUNT) {
                val readIndex = floorMod(writeIndex - delays[channel], historyLength)
                mixed += history[channel][readIndex]
            }
            output[sampleIndex] = mixed / CHANNEL_COUNT / PCM_SCALE

            writeIndex++
            if (writeIndex == historyLength) writeIndex = 0
        }

        return sampleCount
    }

    private fun readPcm16(input: ByteArray, sampleIndex: Int, channel: Int): Int {
        val offset = (sampleIndex * CHANNEL_COUNT + channel) * BYTES_PER_SAMPLE
        return ((input[offset + 1].toInt() shl 8) or
            (input[offset].toInt() and 0xff)).toShort().toInt()
    }

    private fun floorMod(value: Int, modulus: Int): Int {
        val result = value % modulus
        return if (result < 0) result + modulus else result
    }
}
