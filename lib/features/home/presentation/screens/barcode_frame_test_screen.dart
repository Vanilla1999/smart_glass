import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/infrastructure/wear_scan_overlay_sender.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class BarcodeFrameTestScreen extends StatefulWidget {
  const BarcodeFrameTestScreen({super.key});

  @override
  State<BarcodeFrameTestScreen> createState() => _BarcodeFrameTestScreenState();
}

class _BarcodeFrameTestScreenState extends State<BarcodeFrameTestScreen> {
  final WearGlassesBridge _bridge = WearGlassesBridge();
  late final WearScanOverlaySender _overlaySender = WearScanOverlaySender(
    onError: _handleError,
  );
  Future<void> _lifecycle = Future<void>.value();
  String? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = _start();
  }

  Future<void> _start() async {
    try {
      await _bridge.show(const WearGlassesPayload(
        screenType: WearGlassesScreenType.scan,
        phase: WearGlassesPhase.scanning,
        title: 'Проверка рамки',
        subtitle: 'Наведите камеру на штрих-код',
        statusText: 'Поиск ШК...',
        showWifiIcon: false,
      ));
      await _overlaySender.setEnabled(true);
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    debugPrint('[BarcodeFrameTest] $error\n$stackTrace');
    if (mounted) setState(() => _error = error.toString());
  }

  @override
  void dispose() {
    _lifecycle = _lifecycle.then((_) => _stop()).catchError(
      (Object error, StackTrace stackTrace) {
        debugPrint('[BarcodeFrameTest] cleanup failed: $error\n$stackTrace');
      },
    );
    unawaited(_lifecycle);
    super.dispose();
  }

  Future<void> _stop() async {
    await _overlaySender.dispose();
    await _bridge.hide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Тест рамки')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.qr_code_scanner, size: 72),
              const SizedBox(height: 24),
              Text(
                _error == null
                    ? 'Наведите камеру очков на штрих-код.\n'
                        'На дисплее очков должна появиться рамка.'
                    : 'Ошибка запуска:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Завершить тест'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
