package com.example.multi_scanner_example

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** Convert 4-channel UAC4 PCM to the light-denoised mono stream. Mirror of smart_glasses RawLightDenoiser. */
class RawLightDenoiser {
    companion object {
        const val INPUT_FRAME_BYTES = 2048
        const val OUTPUT_FRAME_BYTES = INPUT_FRAME_BYTES / 4
        private const val SAMPLE_RATE = 16_000.0
        private const val FFT_SIZE = 512
        private const val HOP_SIZE = FFT_SIZE / 2
        private const val HIGH_PASS_HZ = 80.0
        private const val HIGH_PASS_Q = 0.7071067811865476
        private const val NOISE_FLOOR_DB = -42.0
        private const val MAX_REDUCTION_DB = 8.0
    }

    private val inputWindow = DoubleArray(FFT_SIZE)
    private val overlap = DoubleArray(HOP_SIZE)
    private val real = DoubleArray(FFT_SIZE)
    private val imaginary = DoubleArray(FFT_SIZE)
    private val window = DoubleArray(FFT_SIZE) { index ->
        sqrt(0.5 - 0.5 * cos(2.0 * PI * index / FFT_SIZE))
    }
    private val windowSum = window.sum()
    private val minimumGain = 10.0.pow(-MAX_REDUCTION_DB / 20.0)
    private val noiseAmplitude = 10.0.pow(NOISE_FLOOR_DB / 20.0)

    private val b0: Double
    private val b1: Double
    private val b2: Double
    private val a1: Double
    private val a2: Double
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    init {
        val omega = 2.0 * PI * HIGH_PASS_HZ / SAMPLE_RATE
        val alpha = sin(omega) / (2.0 * HIGH_PASS_Q)
        val scale = 1.0 / (1.0 + alpha)
        b0 = ((1.0 + cos(omega)) / 2.0) * scale
        b1 = -(1.0 + cos(omega)) * scale
        b2 = b0
        a1 = (-2.0 * cos(omega)) * scale
        a2 = (1.0 - alpha) * scale
    }

    fun reset() {
        inputWindow.fill(0.0)
        overlap.fill(0.0)
        x1 = 0.0
        x2 = 0.0
        y1 = 0.0
        y2 = 0.0
    }

    fun process(input: ByteArray, output: ByteArray): Int {
        require(input.size == INPUT_FRAME_BYTES)
        require(output.size >= OUTPUT_FRAME_BYTES)

        inputWindow.copyInto(inputWindow, 0, HOP_SIZE, FFT_SIZE)
        for (sampleIndex in 0 until HOP_SIZE) {
            var mixed = 0.0
            for (channel in 1..3) {
                val offset = (sampleIndex * 4 + channel) * 2
                val sample = ((input[offset + 1].toInt() shl 8) or
                    (input[offset].toInt() and 0xff)).toShort().toInt()
                mixed += sample / 32768.0
            }
            inputWindow[HOP_SIZE + sampleIndex] = highPass(mixed / 3.0)
        }

        for (index in 0 until FFT_SIZE) {
            real[index] = inputWindow[index] * window[index]
            imaginary[index] = 0.0
        }
        fft(real, imaginary, inverse = false)
        reduceStationaryNoise()
        fft(real, imaginary, inverse = true)

        for (index in 0 until HOP_SIZE) {
            val sample = real[index] * window[index] + overlap[index]
            val pcm = (sample * 32768.0).toInt().coerceIn(-32768, 32767)
            output[index * 2] = pcm.toByte()
            output[index * 2 + 1] = (pcm shr 8).toByte()
            overlap[index] = real[index + HOP_SIZE] * window[index + HOP_SIZE]
        }
        return OUTPUT_FRAME_BYTES
    }

    private fun highPass(input: Double): Double {
        val output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }

    private fun reduceStationaryNoise() {
        for (bin in 0..FFT_SIZE / 2) {
            val power = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
            val noiseMagnitude = noiseAmplitude * windowSum / 2.0
            val noisePower = noiseMagnitude * noiseMagnitude
            val gain = if (power <= noisePower) {
                minimumGain
            } else {
                sqrt((power - noisePower) / power).coerceAtLeast(minimumGain)
            }
            real[bin] *= gain
            imaginary[bin] *= gain
            if (bin > 0 && bin < FFT_SIZE / 2) {
                real[FFT_SIZE - bin] *= gain
                imaginary[FFT_SIZE - bin] *= gain
            }
        }
    }

    private fun fft(real: DoubleArray, imaginary: DoubleArray, inverse: Boolean) {
        var target = 0
        for (source in 1 until FFT_SIZE) {
            var bit = FFT_SIZE shr 1
            while ((target and bit) != 0) {
                target = target xor bit
                bit = bit shr 1
            }
            target = target xor bit
            if (source < target) {
                val realValue = real[source]
                real[source] = real[target]
                real[target] = realValue
                val imaginaryValue = imaginary[source]
                imaginary[source] = imaginary[target]
                imaginary[target] = imaginaryValue
            }
        }

        var length = 2
        while (length <= FFT_SIZE) {
            val angle = (if (inverse) 2.0 else -2.0) * PI / length
            val stepReal = cos(angle)
            val stepImaginary = sin(angle)
            for (start in 0 until FFT_SIZE step length) {
                var twiddleReal = 1.0
                var twiddleImaginary = 0.0
                for (offset in 0 until length / 2) {
                    val even = start + offset
                    val odd = even + length / 2
                    val oddReal = real[odd] * twiddleReal - imaginary[odd] * twiddleImaginary
                    val oddImaginary = real[odd] * twiddleImaginary + imaginary[odd] * twiddleReal
                    real[odd] = real[even] - oddReal
                    imaginary[odd] = imaginary[even] - oddImaginary
                    real[even] += oddReal
                    imaginary[even] += oddImaginary
                    val nextReal = twiddleReal * stepReal - twiddleImaginary * stepImaginary
                    twiddleImaginary = twiddleReal * stepImaginary + twiddleImaginary * stepReal
                    twiddleReal = nextReal
                }
            }
            length = length shl 1
        }
        if (inverse) {
            for (index in 0 until FFT_SIZE) {
                real[index] /= FFT_SIZE
                imaginary[index] /= FFT_SIZE
            }
        }
    }
}
