# Main-app flashlight parity harness

The default example now uses the production Android namespace and reproduces the runtime shape instead of the
old sequential demo:

1. create the primary Flutter engine;
2. create a second Flutter engine and attach it to the glasses display;
3. after the second engine is registered, start `ViScanner.init()`/`prepareForWear()` concurrently with UAC4/SSP voice
   activation and capture;
4. keep both runtimes active while toggling the Movfast flashlight;
5. use the production toggle algorithm (`get` -> tracked state -> `set`) and
   verify the reported state after the write.

The old example packaged `ar_sdk_v1.5.jar`, used extra app permissions, started
scanner before voice, rendered a native Android `Presentation`, and toggled from
its local UI state. Those differences made a successful example run unable to
rule out production-only races or package/classpath behavior.

## Safe parity build

This keeps a separate application id so it can coexist with the production app:

```bash
cd packages/multi_scanner/example
flutter run
```

## Exact application-id experiment

This tests whether the vendor service treats the production package identity
differently. It conflicts with/replaces an installed `ru.tander.smart_glasses`
package and still uses the example's signing key unless you configure identical
signing yourself.

```bash
cd packages/multi_scanner/example/android
./gradlew -PMAIN_APP_IDENTITY_PARITY=true app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Reading the result

Use **Toggle flashlight exactly like main app** and compare:

- `observedBefore`
- `requested`
- `observedAfter`
- `acknowledged`
- `flutterEngineCount`
- `voice.capturing`
- `applicationId` / `identityParity`

Interpretation:

- safe-id parity fails too: package identity is unlikely; focus on concurrent
  SDK initialization, secondary engine registration, or vendor service state;
- safe-id parity works but exact-id parity fails: package/signature/UID handling
  in the vendor service becomes the leading suspect;
- `observedAfter != requested`: the SDK state write itself was not accepted;
- `observedAfter == requested` but the LED is unchanged: the vendor service is
  acknowledging cached/logical state without applying the physical output.
