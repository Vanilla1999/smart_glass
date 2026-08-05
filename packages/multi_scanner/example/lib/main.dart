import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:multi_scanner_example/bluetooth_dialog_portrait_widget.dart';
import 'package:multi_scanner_example/first/cubit/first_screen_cubit.dart';
import 'package:multi_scanner_example/first/cubit/first_screen_state.dart';
import 'package:multi_scanner_example/second/cubit/second_screen_cubit.dart';
import 'package:multi_scanner_example/second/second.dart';
import 'package:multi_scanner_example/third/cubit/third_screen_cubit.dart';
import 'package:multi_scanner_example/third/third.dart';

GetIt getIt = GetIt.instance;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  getIt.registerSingleton<MultiScanner>(MultiScanner.last());
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

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
        create: (_) => FirstScreenCubit()..initScanner(),
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
  int flashlightState = 0;
  String voiceStatus = 'voice: idle';
  bool voiceOn = false;
  bool glassesDisplayOn = false;

  static const _channel = MethodChannel('flashlight_test');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'voiceState') {
        final capturing = call.arguments['capturing'] == true;
        setState(() {
          voiceOn = capturing;
          voiceStatus = capturing ? 'voice: capturing' : 'voice: idle';
        });
      }
    });
  }

  Future<void> _toggleVoice() async {
    try {
      if (voiceOn) {
        final res = await _channel.invokeMethod<String>('stopVoice');
        setState(() {
          voiceOn = false;
          voiceStatus = 'voice: $res';
        });
      } else {
        final res = await _channel.invokeMethod<String>('startVoice');
        setState(() {
          voiceOn = true;
          voiceStatus = 'voice: $res';
        });
      }
    } catch (e) {
      setState(() {
        voiceStatus = 'voice error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner + Voice Test'),
      ),
      body: BlocBuilder<FirstScreenCubit, FirstScreenState>(
        buildWhen: (previousState, state) {
          return state.when(
              loading: () => true, suc: () => true, onScan: (barcode) => false);
        },
        builder: _builder,
      ),
    );
  }

  Widget _builder(BuildContext context, FirstScreenState state) {
    final cubit = context.read<FirstScreenCubit>();
    final scannerController = MultiScannerController();
    bool flag = false;
    return SingleChildScrollView(
      child: Column(
        children: [
          BlocBuilder<FirstScreenCubit, FirstScreenState>(
              buildWhen: (previousState, state) {
            return state.maybeWhen(
                onScan: (barcode) => true, orElse: () => false);
          }, builder: (context, state) {
            return state.maybeWhen(
                onScan: (barcode) => Center(
                      child: Text('Running on: $barcode\n'),
                    ),
                orElse: () => const SizedBox.shrink());
          }),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamed(SecondScreen.route);
            },
            child: const Text("нажми"),
          ),
          ElevatedButton(
            onPressed: () {
              cubit.goToCOMMode(flag);
              flag = !flag;
            },
            child: const Text("goToCOMMode"),
          ),
          ElevatedButton(
            onPressed: () {
              cubit.goToHIDMode();
              flag = !flag;
            },
            child: const Text("goToHIDMode"),
          ),
          ElevatedButton(
            onPressed: () {
              cubit.scanBarcodeByCamera();
            },
            child: const Text("scanBarcode"),
          ),
          ElevatedButton(
            onPressed: () async {
              const tag = '[FlashlightTrace]';
              debugPrint('$tag prepareForWear begin');
              await BaseController().prepareForWear();
              debugPrint('$tag prepareForWear done — scanner active');
              setState(() {
                voiceStatus = 'scanner: active (prepareForWear)';
              });
            },
            child: const Text("startScanning"),
          ),
          ElevatedButton(
            onPressed: () async {
              const tag = '[FlashlightTrace]';
              debugPrint('$tag pauseForWear begin');
              await BaseController().pauseForWear();
              debugPrint('$tag pauseForWear done — scanner paused');
              setState(() {
                voiceStatus = 'scanner: paused';
              });
            },
            child: const Text("stopScanning"),
          ),
          ElevatedButton(
            onPressed: () {
              MultiScannerBluetooth().showBluetoothDialog();
            },
            child: const Text("bluetooth"),
          ),
          ElevatedButton(
            onPressed: () {
              cubit.disableScanner();
            },
            child: const Text("disableScanner"),
          ),
          ElevatedButton(
            onPressed: () {
              cubit.enableScanner();
            },
            child: const Text("enableScanner"),
          ),
          const SizedBox(height: 20),
          Text('Flashlight state: $flashlightState',
              style: const TextStyle(fontSize: 16)),
          ElevatedButton(
            onPressed: () async {
              const tag = '[FlashlightTrace]';
              debugPrint('$tag toggle begin, voiceOn=$voiceOn');
              final newState = flashlightState == 0 ? 1 : 0;
              final began = DateTime.now();
              debugPrint('$tag setFlashlight($newState) begin');
              await scannerController.setFlashlight(newState);
              final elapsed =
                  DateTime.now().difference(began).inMilliseconds;
              debugPrint('$tag setFlashlight($newState) done in ${elapsed}ms');
              final state = await scannerController.getFlashlightState();
              debugPrint('$tag getFlashlightState=$state');
              setState(() {
                flashlightState = state;
              });
            },
            child: const Text("toggleFlashlight"),
          ),
          ElevatedButton(
            onPressed: () async {
              const tag = '[FlashlightTrace]';
              debugPrint('$tag === RAPID TOGGLE 10x BEGIN ===');
              for (int i = 0; i < 10; i++) {
                final target = i % 2 == 0 ? 1 : 0;
                final began = DateTime.now();
                debugPrint('$tag rapid #$i setFlashlight($target) begin');
                await scannerController.setFlashlight(target);
                final elapsed =
                    DateTime.now().difference(began).inMilliseconds;
                debugPrint(
                    '$tag rapid #$i setFlashlight($target) done in ${elapsed}ms');
                final state = await scannerController.getFlashlightState();
                debugPrint('$tag rapid #$i getFlashlightState=$state');
                setState(() {
                  flashlightState = state;
                });
                await Future.delayed(const Duration(milliseconds: 200));
              }
              debugPrint('$tag === RAPID TOGGLE 10x END ===');
            },
            child: const Text("Rapid Toggle (10x)"),
          ),
          const SizedBox(height: 20),
          Text(voiceStatus, style: const TextStyle(fontSize: 16)),
          ElevatedButton(
            onPressed: _toggleVoice,
            child: Text(voiceOn ? "Stop Voice" : "Start Voice"),
          ),
          const SizedBox(height: 20),
          Text(
            'Glasses Display: ${glassesDisplayOn ? "ON" : "OFF"}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                if (glassesDisplayOn) {
                  await _channel.invokeMethod('hideGlassesDisplay');
                  setState(() => glassesDisplayOn = false);
                } else {
                  final ok = await _channel.invokeMethod<bool>('showGlassesDisplay') ?? false;
                  setState(() => glassesDisplayOn = ok);
                }
              } catch (e) {
                setState(() => voiceStatus = 'glasses display error: $e');
              }
            },
            child: Text(glassesDisplayOn ? "Hide Glasses Display" : "Show Glasses Display"),
          ),
        ],
      ),
    );
  }
}
