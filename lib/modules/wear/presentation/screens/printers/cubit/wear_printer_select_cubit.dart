import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
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
  }) {
    return WearPrinterSelectState(
      phase: phase ?? this.phase,
      printers: printers ?? this.printers,
      error: clearError ? null : (error ?? this.error),
      whitePrinter: whitePrinter ?? this.whitePrinter,
      yellowPrinter: yellowPrinter ?? this.yellowPrinter,
      step: step ?? this.step,
    );
  }
}

class WearPrinterSelectNotifier extends StateNotifier<WearPrinterSelectState> {
  WearPrinterSelectNotifier({GetAvailablePrintersUseCase? useCase})
      : _useCase = useCase ?? WearDependencies.I.getAvailablePrintersUseCase(),
        super(WearPrinterSelectState.initial()) {
    load();
  }

  final GetAvailablePrintersUseCase _useCase;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(
      phase: WearPrinterSelectPhase.loading,
      clearError: true,
    );
    try {
      final List<AvailablePrinter> printers = await _useCase.call();
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

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
