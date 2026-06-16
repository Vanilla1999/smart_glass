-keep class ru.tander.multi_scanner.** { *; }
-dontwarn ru.tander.multi_scanner.MultiScannerPlugin

# Required by vosk_flutter/JNA in release builds. JNA resolves methods from
# com.sun.jna.Native by exact names from native code, so R8 must not rename or
# strip them.
-keep class com.sun.jna.* { *; }
-keep class * extends com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }
-dontwarn java.awt.**
