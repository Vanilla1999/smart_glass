import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_available_printers_use_case.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';

final AutoDisposeStateNotifierProvider<WearPrinterSelectNotifier,
        WearPrinterSelectState> wearPrinterSelectNotifierProvider =
    StateNotifierProvider.autoDispose<WearPrinterSelectNotifier,
        WearPrinterSelectState>(
  (Ref ref) => WearPrinterSelectNotifier(),
);

enum WearPrinterSelectPhase { idle, loading, error }

enum WearPrinterSelectStep { white, yellow }

class WearPrinterSelectState {
  const WearPrinterSelectState({
    required this.phase,
    required this.printers,
    required this.error,
    required this.whitePrinter,
    required this.yellowPrinter,
    required this.step,
  });

  factory WearPrinterSelectState.initial() {
    return const WearPrinterSelectState(
      phase: WearPrinterSelectPhase.idle,
      printers: <WearPrinter>[],
      error: null,
      whitePrinter: null,
      yellowPrinter: null,
      step: WearPrinterSelectStep.white,
    );
  }

  final WearPrinterSelectPhase phase;
  final List<WearPrinter> printers;
  final String? error;
  final WearPrinter? whitePrinter;
  final WearPrinter? yellowPrinter;
  final WearPrinterSelectStep step;

  bool get isLoading => phase == WearPrinterSelectPhase.loading;
  bool get hasError => error != null;

  WearPrinterSelectState copyWith({
    WearPrinterSelectPhase? phase,
    List<WearPrinter>? printers,
    String? error,
    WearPrinter? whitePrinter,
    WearPrinter? yellowPrinter,
    WearPrinterSelectStep? step,
    bool clearError = false,
    bool clearWhitePrinter = false,
    bool clearYellowPrinter = false,
  }) {
    return WearPrinterSelectState(
      phase: phase ?? this.phase,
      printers: printers ?? this.printers,
      error: clearError ? null : (error ?? this.error),
      whitePrinter:
          clearWhitePrinter ? null : (whitePrinter ?? this.whitePrinter),
      yellowPrinter:
          clearYellowPrinter ? null : (yellowPrinter ?? this.yellowPrinter),
      step: step ?? this.step,
    );
  }
}

class WearPrinterSelectNotifier extends StateNotifier<WearPrinterSelectState> {
  WearPrinterSelectNotifier({GetAvailablePrintersUseCase? useCase})
      : _useCase = useCase,
        super(WearPrinterSelectState.initial()) {
    load();
  }

  final GetAvailablePrintersUseCase? _useCase;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(
      phase: WearPrinterSelectPhase.loading,
      clearError: true,
    );
    try {
      if (WearMockConfig.isEnabled) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        state = state.copyWith(
          phase: WearPrinterSelectPhase.idle,
          printers: const <WearPrinter>[
            WearPrinter(id: 'mock-white-1', name: 'MOCK Белый 1'),
            WearPrinter(id: 'mock-yellow-1', name: 'MOCK Желтый 1'),
            WearPrinter(id: 'mock-mobile-2', name: 'MOCK Мобильный 2'),
          ],
        );
        return;
      }

      final GetAvailablePrintersUseCase useCase =
          _useCase ?? WearDependencies.I.getAvailablePrintersUseCase();
      final List<AvailablePrinter> printers = await useCase.call();
      if (!mounted) return;
      final List<WearPrinter> mapped = printers
          .map(
            (AvailablePrinter printer) => WearPrinter(
              id: printer.number,
              name: printer.name,
            ),
          )
          .toList();
      state = state.copyWith(
        phase: WearPrinterSelectPhase.idle,
        printers: mapped,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        phase: WearPrinterSelectPhase.error,
        error: _asUiMessage(error),
      );
    }
  }

  void selectPrinter(WearPrinter printer) {
    if (state.step == WearPrinterSelectStep.white) {
      state = state.copyWith(
        whitePrinter: printer,
        step: WearPrinterSelectStep.yellow,
      );
      return;
    }
    if (state.whitePrinter?.id == printer.id) {
      return;
    }
    state = state.copyWith(yellowPrinter: printer);
  }

  void resetSelection() {
    state = state.copyWith(
      clearWhitePrinter: true,
      clearYellowPrinter: true,
      step: WearPrinterSelectStep.white,
    );
  }

  void restoreState(WearPrinterSelectState next) {
    state = next;
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
