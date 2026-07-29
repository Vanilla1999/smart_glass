-keep class ru.tander.multi_scanner.** { *; }
-dontwarn ru.tander.multi_scanner.MultiScannerPlugin

# Required by vosk_flutter/JNA in release builds. JNA resolves methods from
# com.sun.jna.Native by exact names from native code, so R8 must not rename or
# strip them.
-keep class com.sun.jna.* { *; }
-keep class * extends com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }
-dontwarn java.awt.**

# UAC4 AIDL stubs and vendor SSP/activation entry points are loaded externally.
-keep class com.xcheng.uac4client.** { *; }
-keep class com.unisound.** { *; }
