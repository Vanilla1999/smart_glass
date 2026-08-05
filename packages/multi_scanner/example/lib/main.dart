import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:multi_scanner_example/first/cubit/first_screen_cubit.dart';
import 'package:multi_scanner_example/first/cubit/first_screen_state.dart';
import 'package:multi_scanner_example/main_app_parity_runtime.dart';
import 'package:multi_scanner_example/second/cubit/second_screen_cubit.dart';
import 'package:multi_scanner_example/second/second.dart';
import 'package:multi_scanner_example/third/cubit/third_screen_cubit.dart';
import 'package:multi_scanner_example/third/third.dart';

GetIt getIt = GetIt.instance;

@pragma('vm:entry-point')
void glassesMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ParityGlassesApp());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  getIt.registerSingleton<MultiScanner>(MultiScanner.last());
  runApp(const MyApp());
}

class _ParityGlassesApp extends StatelessWidget {
  const _ParityGlassesApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Secondary Flutter engine active',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        SecondScreen.route: (context) => BlocProvider(
          create: (_) => SecondScreenCubit()..initScanner(),
          child: const SecondScreen(),
        ),
        ThirdScreen.route: (context) => BlocProvider(
          create: (_) => ThirdScreenCubit()..initScanner(),
          child: const ThirdScreen(),
        ),
      },
      home: BlocProvider(
        // Main-app parity startup owns scanner initialization so it can overlap
        // UAC4 voice startup instead of completing before the test begins.
        create: (_) => FirstScreenCubit(),
        child: const NewWidget(),
      ),
    );
  }
}

class NewWidget extends StatefulWidget {
  const NewWidget({super.key});

  @override
  State<NewWidget> createState() => _NewWidgetState();
}

class _NewWidgetState extends State<NewWidget> {
  static const MethodChannel _channel = MethodChannel('flashlight_test');

  late final MainAppParityRuntime _parityRuntime;
  int flashlightState = 0;
  String voiceStatus = 'voice: idle';
  String parityStatus = 'parity: not started';
  bool voiceOn = false;
  bool glassesDisplayOn = false;
  bool parityStarting = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'voiceState' || !mounted) return;
      final dynamic arguments = call.arguments;
      final bool capturing = arguments is Map && arguments['capturing'] == true;
      setState(() {
        voiceOn = capturing;
        voiceStatus = capturing ? 'voice: capturing' : 'voice: idle';
      });
    });
    final MovfastGlassController flashlight = MovfastGlassController();
    _parityRuntime = MainAppParityRuntime(
      startScanner: () =>
          context.read<FirstScreenCubit>().startMainAppParityScanner(),
      startVoice: () async =>
          await _channel.invokeMethod<String>('startVoice') ?? 'unknown',
      showGlassesDisplay: () async =>
          await _channel.invokeMethod<bool>('showGlassesDisplay') ?? false,
      getFlashlightState: flashlight.getFlashlightState,
      setFlashlight: flashlight.setFlashlight,
      nativeDiagnostics: _nativeDiagnostics,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startMainAppParity());
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<Map<String, dynamic>> _nativeDiagnostics() async {
    final Map<dynamic, dynamic>? raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('getParityNativeDiagnostics');
    if (raw == null) return const <String, dynamic>{};
    return raw.map<String, dynamic>(
      (dynamic key, dynamic value) =>
          MapEntry<String, dynamic>(key.toString(), value),
    );
  }

  Future<void> _startMainAppParity() async {
    if (parityStarting) return;
    setState(() {
      parityStarting = true;
      parityStatus = 'parity: starting...';
    });
    try {
      final MainAppParityStartReport report = await _parityRuntime.start();
      if (!mounted) return;
      setState(() {
        parityStarting = false;
        voiceOn = report.voiceStatus.contains('captur');
        glassesDisplayOn = report.displayShown;
        voiceStatus = 'voice: ${report.voiceStatus}';
        parityStatus = report.toString();
      });
    } catch (error, stackTrace) {
      debugPrint('[MainAppParity] startup failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        parityStarting = false;
        parityStatus = 'parity error: $error';
      });
    }
  }

  Future<void> _toggleFlashlightLikeMain() async {
    try {
      final FlashlightParityProbe probe = await _parityRuntime
          .toggleFlashlightLikeMain();
      debugPrint('[MainAppParity] $probe');
      if (!mounted) return;
      setState(() {
        flashlightState = probe.observedAfter;
        parityStatus = probe.toString();
      });
    } catch (error, stackTrace) {
      debugPrint('[MainAppParity] flashlight failed: $error\n$stackTrace');
      if (mounted) setState(() => parityStatus = 'flashlight error: $error');
    }
  }

  Future<void> _showDiagnostics() async {
    try {
      final Map<String, dynamic> diagnostics = await _nativeDiagnostics();
      if (mounted) setState(() => parityStatus = 'native=$diagnostics');
    } catch (error) {
      if (mounted) setState(() => parityStatus = 'diagnostics error: $error');
    }
  }

  Future<void> _toggleVoice() async {
    try {
      if (voiceOn) {
        final String? response = await _channel.invokeMethod<String>(
          'stopVoice',
        );
        if (!mounted) return;
        setState(() {
          voiceOn = false;
          voiceStatus = 'voice: $response';
        });
      } else {
        final String? response = await _channel.invokeMethod<String>(
          'startVoice',
        );
        if (!mounted) return;
        setState(() {
          voiceOn = response?.contains('captur') == true;
          voiceStatus = 'voice: $response';
        });
      }
    } catch (error) {
      if (mounted) setState(() => voiceStatus = 'voice error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Main app flashlight parity')),
      body: BlocBuilder<FirstScreenCubit, FirstScreenState>(
        buildWhen: (FirstScreenState previous, FirstScreenState current) {
          return current.when(
            loading: () => true,
            suc: () => true,
            onScan: (_) => false,
          );
        },
        builder: _builder,
      ),
    );
  }

  Widget _builder(BuildContext context, FirstScreenState state) {
    final FirstScreenCubit cubit = context.read<FirstScreenCubit>();
    final MovfastGlassController flashlight = MovfastGlassController();
    var bluetoothDialogFlag = false;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Production parity mode',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(parityStatus),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: parityStarting ? null : _startMainAppParity,
                    child: const Text('Start / read main-app parity runtime'),
                  ),
                  ElevatedButton(
                    onPressed: _toggleFlashlightLikeMain,
                    child: const Text(
                      'Toggle flashlight exactly like main app',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _parityRuntime.resetTrackedFlashlightState();
                      setState(
                        () => parityStatus = 'tracked flashlight state reset',
                      );
                    },
                    child: const Text('Reset tracked flashlight state'),
                  ),
                  ElevatedButton(
                    onPressed: _showDiagnostics,
                    child: const Text('Read native parity diagnostics'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Flashlight state: $flashlightState'),
          Text(voiceStatus),
          Text('Glasses display: ${glassesDisplayOn ? 'ON' : 'OFF'}'),
          const Divider(),
          BlocBuilder<FirstScreenCubit, FirstScreenState>(
            buildWhen: (FirstScreenState previous, FirstScreenState current) {
              return current.maybeWhen(
                onScan: (_) => true,
                orElse: () => false,
              );
            },
            builder: (BuildContext context, FirstScreenState current) {
              return current.maybeWhen(
                onScan: (String barcode) => Text('Running on: $barcode'),
                orElse: () => const SizedBox.shrink(),
              );
            },
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(SecondScreen.route),
            child: const Text('Open second scanner screen'),
          ),
          ElevatedButton(
            onPressed: () {
              cubit.goToCOMMode(bluetoothDialogFlag);
              bluetoothDialogFlag = !bluetoothDialogFlag;
            },
            child: const Text('Show Bluetooth dialog'),
          ),
          ElevatedButton(
            onPressed: cubit.goToHIDMode,
            child: const Text('goToHIDMode'),
          ),
          ElevatedButton(
            onPressed: cubit.scanBarcodeByCamera,
            child: const Text('scanBarcode'),
          ),
          ElevatedButton(
            onPressed: () async {
              await cubit.initScanner();
              if (mounted) {
                setState(
                  () => parityStatus = 'original example init completed',
                );
              }
            },
            child: const Text('Run original example scanner init'),
          ),
          ElevatedButton(
            onPressed: () async {
              await BaseController().pauseForWear();
              if (mounted) setState(() => parityStatus = 'scanner paused');
            },
            child: const Text('pauseForWear'),
          ),
          ElevatedButton(
            onPressed: cubit.disableScanner,
            child: const Text('disableScanner'),
          ),
          ElevatedButton(
            onPressed: cubit.enableScanner,
            child: const Text('enableScanner'),
          ),
          ElevatedButton(
            onPressed: _toggleVoice,
            child: Text(voiceOn ? 'Stop Voice' : 'Start Voice'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (glassesDisplayOn) {
                await _channel.invokeMethod<void>('hideGlassesDisplay');
                if (mounted) setState(() => glassesDisplayOn = false);
              } else {
                final bool shown =
                    await _channel.invokeMethod<bool>('showGlassesDisplay') ??
                    false;
                if (mounted) setState(() => glassesDisplayOn = shown);
              }
            },
            child: Text(
              glassesDisplayOn
                  ? 'Hide secondary Flutter engine'
                  : 'Show secondary Flutter engine',
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              // Baseline direct write, retained for A/B comparison with the
              // production read/track/write path above.
              final int target = flashlightState == 0 ? 1 : 0;
              await flashlight.setFlashlight(target);
              final int observed = await flashlight.getFlashlightState();
              if (mounted) setState(() => flashlightState = observed);
            },
            child: const Text('Baseline direct flashlight toggle'),
          ),
          ElevatedButton(
            onPressed: () async {
              for (var index = 0; index < 10; index++) {
                final int target = index.isEven ? 1 : 0;
                await flashlight.setFlashlight(target);
                final int observed = await flashlight.getFlashlightState();
                if (mounted) setState(() => flashlightState = observed);
                await Future<void>.delayed(const Duration(milliseconds: 200));
              }
            },
            child: const Text('Rapid Toggle (10x)'),
          ),
        ],
      ),
    );
  }
}
