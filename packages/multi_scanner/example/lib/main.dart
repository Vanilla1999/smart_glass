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

  // Platform messages are asynchronous, so we initialize in an async method.

// 3 экрана/
//
// 1 textField + ряд кнопок, включая на некст экран. Экран без сканирования, Экран со сканированием и экран с удалением стэка
// Диалоговое окно
//
// /
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
  const NewWidget({
    super.key,
  });

  @override
  State<NewWidget> createState() => _NewWidgetState();
}

class _NewWidgetState extends State<NewWidget> {
  int flashlightState = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('1'),
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
    return state.maybeWhen(
        loading: () => Column(
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
                      orElse: () => Container(
                            color: Colors.red,
                          ));
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
                Text('Flashlight state: $flashlightState'),
                ElevatedButton(
                  onPressed: () async {
                    final newState = flashlightState == 0 ? 1 : 0;
                    await scannerController.setFlashlight(newState);
                    final state = await scannerController.getFlashlightState();
                    setState(() {
                      flashlightState = state;
                    });
                  },
                  child: const Text("toggleFlashlight"),
                ),
              ],
            ),
        orElse: () => Container(
              color: Colors.red,
            ));
  }
}
