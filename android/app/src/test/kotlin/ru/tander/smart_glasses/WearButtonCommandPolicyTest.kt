package ru.tander.smart_glasses

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WearButtonCommandPolicyTest {
    @Test
    fun normalizesOnlySupportedCommands() {
        assertEquals("up", WearButtonCommandPolicy.normalize(" UP "))
        assertEquals("down", WearButtonCommandPolicy.normalize("Down"))
        assertEquals("enter", WearButtonCommandPolicy.normalize("enter"))
        assertNull(WearButtonCommandPolicy.normalize("back"))
        assertNull(WearButtonCommandPolicy.normalize(null))
    }

    @Test
    fun rejectsObservedForeignSender() {
        assertTrue(
            WearButtonCommandPolicy.acceptsObservedSender(
                WearButtonCommandPolicy.UAC4_PACKAGE,
                "ru.tander.smart_glasses",
            ),
        )
        assertTrue(
            WearButtonCommandPolicy.acceptsObservedSender(
                "ru.tander.smart_glasses",
                "ru.tander.smart_glasses",
            ),
        )
        assertFalse(
            WearButtonCommandPolicy.acceptsObservedSender(
                "example.attacker",
                "ru.tander.smart_glasses",
            ),
        )
    }

    @Test
    fun acceptsMissingSenderIdentityForLegacyUac4Compatibility() {
        assertTrue(
            WearButtonCommandPolicy.acceptsObservedSender(
                null,
                "ru.tander.smart_glasses",
            ),
        )
    }
}
