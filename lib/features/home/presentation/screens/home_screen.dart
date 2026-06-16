import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/app/di/app_scope.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_cubit.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_state.dart';
import 'package:smart_glasses/features/home/presentation/widgets/barcode_display_card.dart';
import 'package:smart_glasses/features/home/presentation/widgets/control_buttons.dart';
import 'package:smart_glasses/features/home/presentation/widgets/counter_display.dart';
import 'package:smart_glasses/features/home/presentation/widgets/voice_recognition_button.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_cubit.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_state.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_cubit.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_state.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_module_app.dart';

/// Home screen
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: dependencies.homeCubit),
        BlocProvider.value(value: dependencies.scannerCubit),
        BlocProvider.value(value: dependencies.voiceCubit),
      ],
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  const _HomeScreenContent();

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> {
  Future<void> _openWearModule(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('WEAR_USE_MOCKS', true);
    await prefs.setBool('WEAR_MOCK_AUTH', true);
    WearDependencies.I.resetAuthDependencies();
    unawaited(WearDependencies.I.ensureVoiceTypingPrepared());

    if (!context.mounted) {
      return;
    }
    print('[STACK-DEBUG] HomeScreen: pushing WearModuleApp mock route');
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/wear_module_mock'),
        builder: (_) => ProviderScope(
          child: const WearModuleApp(),
        ),
      ),
    );
    print('[STACK-DEBUG] HomeScreen: WearModuleApp mock route popped');
  }

  Future<void> _openWearModuleReal(BuildContext context) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _RealModeDbDialog(),
    );

    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();
    // DBTO (Firebird)
    await prefs.setString('DBTO_HOST', result['dbto_host']!);
    await prefs.setString('DBTO_PORT', result['dbto_port']!);
    await prefs.setString('DBTO_PATH', result['dbto_path']!);
    await prefs.setString('DBTO_USER', result['dbto_user']!);
    await prefs.setString('DBTO_PASSWORD', result['dbto_password']!);
    await prefs.setString('DBTO_ROLE', result['dbto_role']!);
    // Auth Service
    await prefs.setString('AUTH_SERVICE_HOST', result['auth_host']!);
    await prefs.setString('AUTH_SERVICE_PORT', result['auth_port']!);
    // Disable mocks for real mode
    await prefs.setBool('WEAR_USE_MOCKS', false);
    await prefs.setBool('WEAR_MOCK_AUTH', false);
    WearDependencies.I.resetAuthDependencies();

    if (context.mounted) {
      unawaited(WearDependencies.I.ensureVoiceTypingPrepared());
      print('[STACK-DEBUG] HomeScreen: pushing WearModuleApp real route');
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/wear_module_real'),
          builder: (_) => ProviderScope(
            child: const WearModuleApp(),
          ),
        ),
      );
      print('[STACK-DEBUG] HomeScreen: WearModuleApp real route popped');
    }
  }

  Future<void> _openWearModuleTest(BuildContext context) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _TestModeDbDialog(),
    );

    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();
    // DBTO (Firebird)
    await prefs.setString('DBTO_HOST', result['dbto_host']!);
    await prefs.setString('DBTO_PORT', result['dbto_port']!);
    await prefs.setString('DBTO_PATH', result['dbto_path']!);
    await prefs.setString('DBTO_USER', result['dbto_user']!);
    await prefs.setString('DBTO_PASSWORD', result['dbto_password']!);
    await prefs.setString('DBTO_ROLE', result['dbto_role']!);
    // Auth Service
    await prefs.setString('AUTH_SERVICE_HOST', result['auth_host']!);
    await prefs.setString('AUTH_SERVICE_PORT', result['auth_port']!);
    // Test mode uses the test DB/auth hosts, but still loads printers/products
    // from the network instead of returning hardcoded mock data.
    await prefs.setBool('WEAR_USE_MOCKS', false);
    // Auth service can be unavailable from the test network/PC, so test price
    // label flow may mock authorization while keeping Firebird data real.
    await prefs.setBool('WEAR_MOCK_AUTH', true);
    WearDependencies.I.resetAuthDependencies();

    if (context.mounted) {
      unawaited(WearDependencies.I.ensureVoiceTypingPrepared());
      print('[STACK-DEBUG] HomeScreen: pushing WearModuleApp test route');
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/wear_module_test'),
          builder: (_) => ProviderScope(
            child: const WearModuleApp(),
          ),
        ),
      );
      print('[STACK-DEBUG] HomeScreen: WearModuleApp test route popped');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('Smart Wear Test'),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BlocBuilder<HomeCubit, HomeState>(
                  builder: (context, state) {
                    if (state is HomeLoaded) {
                      return ControlButtons(
                        onSaveLogs: () => context.read<HomeCubit>().saveLogs(),
                        onClearLogs: () =>
                            context.read<HomeCubit>().clearLogs(),
                        onIncrementCounter: () =>
                            context.read<HomeCubit>().incrementCounter(),
                        onPrintTags: () => _openWearModule(context),
                        onPrintTagsReal: () => _openWearModuleReal(context),
                        onPrintTagsTest: () => _openWearModuleTest(context),
                      );
                    }
                    return const CircularProgressIndicator();
                  },
                ),
                const SizedBox(height: 40),
                BlocBuilder<HomeCubit, HomeState>(
                  builder: (context, state) {
                    if (state is HomeLoaded) {
                      return CounterDisplay(counter: state.counter);
                    }
                    return const CounterDisplay(counter: 0);
                  },
                ),
                const SizedBox(height: 10),
                BlocBuilder<VoiceCubit, VoiceState>(
                  builder: (context, state) {
                    if (state is VoiceInitializing) {
                      return Text(
                        'Загрузка модели...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    } else if (state is VoiceRecognized) {
                      return Text(
                        'Распознано: ${state.text}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    } else if (state is VoiceError) {
                      return Text(
                        'Ошибка: ${state.message}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.red),
                      );
                    }
                    return Text(
                      'Распознано: ',
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  },
                ),
                const SizedBox(height: 20),
                BlocBuilder<ScannerCubit, ScannerState>(
                  builder: (context, state) {
                    String barcode = '';
                    if (state is ScannerScanned) {
                      barcode = state.barcode;
                    }
                    return BarcodeDisplayCard(barcode: barcode);
                  },
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            BlocBuilder<VoiceCubit, VoiceState>(
              builder: (context, state) {
                final isReady = state is VoiceReady ||
                    state is VoiceListening ||
                    state is VoiceRecognized;
                final isListening = state is VoiceListening;

                return VoiceRecognitionButton(
                  isReady: isReady,
                  isListening: isListening,
                  onPressed: () {
                    if (isListening) {
                      context.read<VoiceCubit>().stopListening();
                    } else {
                      context.read<VoiceCubit>().startListening();
                    }
                  },
                );
              },
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _RealModeDbDialog extends StatefulWidget {
  const _RealModeDbDialog();

  @override
  State<_RealModeDbDialog> createState() => _RealModeDbDialogState();
}

class _RealModeDbDialogState extends State<_RealModeDbDialog> {
  final _dbtoHostController = TextEditingController(text: '192.168.140.1');
  final _dbtoPortController = TextEditingController(text: '3050');
  final _dbtoPathController = TextEditingController(text: '/base/ws578096.gdb');
  final _dbtoUserController = TextEditingController(text: 'C_WATCH');
  final _dbtoPasswordController = TextEditingController(text: 'RiKfr8EP');
  final _dbtoRoleController = TextEditingController(text: 'R_TSDSERVER');
  final _authHostController = TextEditingController(text: '192.168.140.1');
  final _authPortController = TextEditingController(text: '9950');

  @override
  void dispose() {
    _dbtoHostController.dispose();
    _dbtoPortController.dispose();
    _dbtoPathController.dispose();
    _dbtoUserController.dispose();
    _dbtoPasswordController.dispose();
    _dbtoRoleController.dispose();
    _authHostController.dispose();
    _authPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Боевые параметры'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('--- DBTO (Firebird) ---',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: _dbtoHostController,
                decoration: const InputDecoration(labelText: 'DBTO_HOST')),
            TextField(
                controller: _dbtoPortController,
                decoration: const InputDecoration(labelText: 'DBTO_PORT'),
                keyboardType: TextInputType.number),
            TextField(
                controller: _dbtoPathController,
                decoration: const InputDecoration(labelText: 'DBTO_PATH')),
            TextField(
                controller: _dbtoUserController,
                decoration: const InputDecoration(labelText: 'DBTO_USER')),
            TextField(
                controller: _dbtoPasswordController,
                decoration: const InputDecoration(labelText: 'DBTO_PASSWORD'),
                obscureText: true),
            TextField(
                controller: _dbtoRoleController,
                decoration: const InputDecoration(labelText: 'DBTO_ROLE')),
            const SizedBox(height: 16),
            const Text('--- Auth Service ---',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: _authHostController,
                decoration: const InputDecoration(labelText: 'AUTH_HOST')),
            TextField(
                controller: _authPortController,
                decoration: const InputDecoration(labelText: 'AUTH_PORT'),
                keyboardType: TextInputType.number),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'dbto_host': _dbtoHostController.text,
              'dbto_port': _dbtoPortController.text,
              'dbto_path': _dbtoPathController.text,
              'dbto_user': _dbtoUserController.text,
              'dbto_password': _dbtoPasswordController.text,
              'dbto_role': _dbtoRoleController.text,
              'auth_host': _authHostController.text,
              'auth_port': _authPortController.text,
            });
          },
          child: const Text('Запустить'),
        ),
      ],
    );
  }
}

class _TestModeDbDialog extends StatefulWidget {
  const _TestModeDbDialog();

  @override
  State<_TestModeDbDialog> createState() => _TestModeDbDialogState();
}

class _TestModeDbDialogState extends State<_TestModeDbDialog> {
  final _dbtoHostController = TextEditingController(text: '10.8.34.232');
  final _dbtoPortController = TextEditingController(text: '3050');
  final _dbtoPathController = TextEditingController(text: '/base/test.gdb');
  final _dbtoUserController = TextEditingController(text: 'C_WATCH');
  final _dbtoPasswordController = TextEditingController(text: 'RiKfr8EP');
  final _dbtoRoleController = TextEditingController(text: 'R_TSDSERVER');
  final _authHostController = TextEditingController(text: '10.8.34.232');
  final _authPortController = TextEditingController(text: '9950');

  @override
  void dispose() {
    _dbtoHostController.dispose();
    _dbtoPortController.dispose();
    _dbtoPathController.dispose();
    _dbtoUserController.dispose();
    _dbtoPasswordController.dispose();
    _dbtoRoleController.dispose();
    _authHostController.dispose();
    _authPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Тестовые параметры'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('--- DBTO (Firebird) ---',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: _dbtoHostController,
                decoration: const InputDecoration(labelText: 'DBTO_HOST')),
            TextField(
                controller: _dbtoPortController,
                decoration: const InputDecoration(labelText: 'DBTO_PORT'),
                keyboardType: TextInputType.number),
            TextField(
                controller: _dbtoPathController,
                decoration: const InputDecoration(labelText: 'DBTO_PATH')),
            TextField(
                controller: _dbtoUserController,
                decoration: const InputDecoration(labelText: 'DBTO_USER')),
            TextField(
                controller: _dbtoPasswordController,
                decoration: const InputDecoration(labelText: 'DBTO_PASSWORD'),
                obscureText: true),
            TextField(
                controller: _dbtoRoleController,
                decoration: const InputDecoration(labelText: 'DBTO_ROLE')),
            const SizedBox(height: 16),
            const Text('--- Auth Service ---',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: _authHostController,
                decoration: const InputDecoration(labelText: 'AUTH_HOST')),
            TextField(
                controller: _authPortController,
                decoration: const InputDecoration(labelText: 'AUTH_PORT'),
                keyboardType: TextInputType.number),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'dbto_host': _dbtoHostController.text,
              'dbto_port': _dbtoPortController.text,
              'dbto_path': _dbtoPathController.text,
              'dbto_user': _dbtoUserController.text,
              'dbto_password': _dbtoPasswordController.text,
              'dbto_role': _dbtoRoleController.text,
              'auth_host': _authHostController.text,
              'auth_port': _authPortController.text,
            });
          },
          child: const Text('Запустить'),
        ),
      ],
    );
  }
}
