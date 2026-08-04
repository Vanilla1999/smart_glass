package ru.tander.smart_glasses

internal object WearButtonCommandPolicy {
    const val ACTION = "test"
    const val VALUE_EXTRA = "value"
    const val UAC4_PACKAGE = "com.xcheng.uac4client"

    private val allowedCommands = setOf("up", "down", "enter")

    fun normalize(rawValue: String?): String? {
        val normalized = rawValue?.trim()?.lowercase() ?: return null
        return normalized.takeIf(allowedCommands::contains)
    }

    /**
     * Android only exposes the sender package when the sender shares its
     * identity. A missing identity is accepted for compatibility with the
     * current UAC4 client; an observed foreign package is always rejected.
     */
    fun acceptsObservedSender(
        observedPackage: String?,
        ownPackage: String,
    ): Boolean {
        return observedPackage == null ||
            observedPackage == ownPackage ||
            observedPackage == UAC4_PACKAGE
    }
}
