package audiofrontendab

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import ru.tander.smart_glasses.voice.RawChannelMixMode
import ru.tander.smart_glasses.voice.RawLightDenoiser

private data class Wav(val sampleRate: Int, val channels: Int, val bitsPerSample: Int, val pcm: ByteArray)

fun main(args: Array<String>) {
    require(args.size == 2) { "Usage: RawDenoiserWavRunner <raw-4ch-wav> <output-directory>" }
    val input = File(args[0])
    val outputDirectory = File(args[1]).also { it.mkdirs() }
    val wav = readWav(input)
    require(wav.sampleRate == 16_000) { "Expected 16000 Hz, got ${wav.sampleRate}" }
    require(wav.channels == 4) { "Expected four channels, got ${wav.channels}" }
    require(wav.bitsPerSample == 16) { "Expected PCM16, got ${wav.bitsPerSample} bits" }
    require(wav.pcm.size % 8 == 0) { "PCM data does not contain whole four-channel frames" }

    val id = input.name.removePrefix("raw_4ch_").removeSuffix(".wav")
    RawChannelMixMode.entries.forEach { mode ->
        val output = process(wav.pcm, mode)
        val name = when (mode) {
            RawChannelMixMode.LEGACY_CHANNELS_1_TO_3 -> "legacy_denoised_$id.wav"
            RawChannelMixMode.ALIGNED_FOUR_CHANNEL -> "aligned_denoised_$id.wav"
        }
        writeWav(File(outputDirectory, name), sampleRate = 16_000, channels = 1, pcm = output)
        println("mode=$mode input=${wav.pcm.size} output=${output.size} path=${File(outputDirectory, name).absolutePath}")
    }
}

private fun process(input: ByteArray, mode: RawChannelMixMode): ByteArray {
    val denoiser = RawLightDenoiser(mode)
    val frameBytes = RawLightDenoiser.INPUT_FRAME_BYTES
    val outputFrameBytes = RawLightDenoiser.OUTPUT_FRAME_BYTES
    val completeFrames = input.size / frameBytes
    val remainder = input.size % frameBytes
    val frames = completeFrames + if (remainder == 0) 0 else 1
    val output = ByteArray(frames * outputFrameBytes)

    repeat(frames) { frameIndex ->
        val frame = ByteArray(frameBytes)
        val offset = frameIndex * frameBytes
        val copied = minOf(frameBytes, input.size - offset)
        input.copyInto(frame, 0, offset, offset + copied)
        val processed = ByteArray(outputFrameBytes)
        denoiser.process(frame, processed)
        processed.copyInto(output, frameIndex * outputFrameBytes)
    }

    // A padded input tail emits a padded mono tail. Retain exactly the original frame count.
    return output.copyOf(input.size / 4)
}

private fun readWav(file: File): Wav {
    val bytes = file.readBytes()
    require(bytes.size >= 44 && bytes.copyOfRange(0, 4).decodeToString() == "RIFF") { "Not a RIFF WAV: ${file.path}" }
    require(bytes.copyOfRange(8, 12).decodeToString() == "WAVE") { "Not a WAVE file: ${file.path}" }
    var cursor = 12
    var sampleRate: Int? = null
    var channels: Int? = null
    var bitsPerSample: Int? = null
    var pcm: ByteArray? = null
    while (cursor + 8 <= bytes.size) {
        val id = bytes.copyOfRange(cursor, cursor + 4).decodeToString()
        val size = littleEndianInt(bytes, cursor + 4)
        val payload = cursor + 8
        require(size >= 0 && payload + size <= bytes.size) { "Invalid $id chunk in ${file.path}" }
        if (id == "fmt ") {
            require(size >= 16) { "Short fmt chunk in ${file.path}" }
            require(littleEndianShort(bytes, payload) == 1) { "Expected PCM format in ${file.path}" }
            channels = littleEndianShort(bytes, payload + 2)
            sampleRate = littleEndianInt(bytes, payload + 4)
            bitsPerSample = littleEndianShort(bytes, payload + 14)
        } else if (id == "data") {
            pcm = bytes.copyOfRange(payload, payload + size)
        }
        cursor = payload + size + (size and 1)
    }
    return Wav(sampleRate ?: error("Missing fmt chunk"), channels ?: error("Missing fmt chunk"), bitsPerSample ?: error("Missing fmt chunk"), pcm ?: error("Missing data chunk"))
}

private fun writeWav(file: File, sampleRate: Int, channels: Int, pcm: ByteArray) {
    val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
    header.put("RIFF".encodeToByteArray())
    header.putInt(36 + pcm.size)
    header.put("WAVEfmt ".encodeToByteArray())
    header.putInt(16)
    header.putShort(1)
    header.putShort(channels.toShort())
    header.putInt(sampleRate)
    header.putInt(sampleRate * channels * 2)
    header.putShort((channels * 2).toShort())
    header.putShort(16)
    header.put("data".encodeToByteArray())
    header.putInt(pcm.size)
    file.outputStream().use { stream -> stream.write(header.array()); stream.write(pcm) }
}

private fun littleEndianShort(bytes: ByteArray, offset: Int): Int =
    (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

private fun littleEndianInt(bytes: ByteArray, offset: Int): Int =
    (bytes[offset].toInt() and 0xff) or
        ((bytes[offset + 1].toInt() and 0xff) shl 8) or
        ((bytes[offset + 2].toInt() and 0xff) shl 16) or
        (bytes[offset + 3].toInt() shl 24)
