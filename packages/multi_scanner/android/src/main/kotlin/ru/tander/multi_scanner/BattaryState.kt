package ru.tander.multi_scanner

import ru.tander.viScanner.bluetooth.adapters.BTDevice

data class BattaryState(val device: BTDevice, val battary: String)
