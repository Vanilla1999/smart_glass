import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/auth/use_case/authenticate_user_use_case.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/utils/wear_feedback.dart';

final AutoDisposeStateNotifierProvider<WearAuthNotifier, WearAuthState>
    wearAuthNotifierProvider =
    StateNotifierProvider.autoDispose<WearAuthNotifier, WearAuthState>(
  (Ref ref) => WearAuthNotifier(ref),
);

enum WearAuthPhase { idle, loading }

class WearAuthState {
  const WearAuthState({
    required this.phase,
    required this.nav,
  });

  factory WearAuthState.initial() {
    return const WearAuthState(
      phase: WearAuthPhase.idle,
      nav: null,
    );
  }

  final WearAuthPhase phase;
  final WearStatusScreenArgs? nav;

  bool get isLoading => phase == WearAuthPhase.loading;

  WearAuthState copyWith({
    WearAuthPhase? phase,
    WearStatusScreenArgs? nav,
    bool clearNav = false,
  }) {
    return WearAuthState(
      phase: phase ?? this.phase,
      nav: clearNav ? null : (nav ?? this.nav),
    );
  }
}

class WearAuthNotifier extends StateNotifier<WearAuthState>
    implements MultiScannerDelegate {
  WearAuthNotifier(Ref ref) : super(WearAuthState.initial()) {
    _scanner.addDelegate(this);
  }

  final MultiScanner _scanner = MultiScanner.last();

  static const String _mockLogoBarcode =
      '{"uuid": "be9f894e-bebe-11f0-ccaf-00e04c1521d1", "kiscode": "mmmkakoikiss", "version": 2}';
  static const String _realLogoBarcode =
      '{"uuid": "ee5a9032-4731-467b-af02-3becca71f0e8", "kiscode": "CN0-119184", "version": 1}';
  static final AuthenticatedUser _mockSkipUser = AuthenticatedUser(
    idUser: 872,
    idEmployee: 2157,
    name: 'Колиус',
  );

  @override
  void dispose() {
    _scanner.removeDelegate(this);
    super.dispose();
  }

  @override
  bool? onScanEvent(String payload) {
    print('[AUTH] onScanEvent called, payload: $payload');
    if (WearSession.isAuthorized) {
      print('[AUTH] Already authorized, ignoring');
      return true;
    }
    authorizeByBadgeBarcode(payload);
    return true;
  }

  @override
  bool? onErrorScan(Exception error) {
    return false;
  }

  Future<void> handleLogoTap() async {
    if (WearSession.isAuthorized) {
      print('[AUTH] handleLogoTap ignored: already authorized');
      return;
    }
    final bool useAuthMock =
        WearMockConfig.isEnabled || await _isAuthMockEnabled();
    print('[AUTH] handleLogoTap useAuthMock=$useAuthMock');
    if (!useAuthMock) {
      print('[AUTH] handleLogoTap using real logo barcode');
      await authorizeByBadgeBarcode(_realLogoBarcode);
      return;
    }
    print('[AUTH] handleLogoTap using mock logo barcode');
    await authorizeByBadgeBarcode(_mockLogoBarcode);
  }

  Future<void> handleLogoLongPress() async {
    if (WearSession.isAuthorized) {
      return;
    }
    if (!_isMockLogoSkipAuthEnabled()) {
      return;
    }
    if (state.isLoading) return;

    state = state.copyWith(phase: WearAuthPhase.loading);

    try {
      // await WearDependencies.I.ensureBdtoOpened();

      WearSession.setUser(_mockSkipUser);

      await WearFeedback.play(WearStatusKind.success);
      state = state.copyWith(
        phase: WearAuthPhase.idle,
        nav: WearStatusScreenArgs(
          kind: WearStatusKind.success,
          title: 'Вошли как',
          message: _mockSkipUser.name,
          autoAfter: const Duration(seconds: 2),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    } catch (error) {
      await WearFeedback.play(WearStatusKind.error);
      state = state.copyWith(
        phase: WearAuthPhase.idle,
        nav: WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка входа',
          message: _asUiMessage(error),
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    }
  }

  Future<void> authorizeByBadgeBarcode(String barcode) async {
    print('[AUTH] authorizeByBadgeBarcode called, barcode: $barcode');
    if (WearSession.isAuthorized) {
      print('[AUTH] Already authorized, returning');
      return;
    }
    if (state.isLoading) {
      print('[AUTH] Already loading, returning');
      return;
    }

    final String trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) {
      print('[AUTH] Empty barcode, returning');
      return;
    }
    print('[AUTH] Starting authorization...');

    state = state.copyWith(phase: WearAuthPhase.loading);

    try {
      if (WearMockConfig.isEnabled || await _isAuthMockEnabled()) {
        print('[AUTH] Using mock authorization');
        await _authorizeWithMockUser();
        return;
      }

      print('[AUTH] Using real authorization');

      // 0) поднимаем соединение с БД объекта сразу
      // await WearDependencies.I.ensureBdtoOpened();

      // 1) аутентификация
      final AuthenticateUserUseCase useCase =
          await WearDependencies.I.authenticateUserUseCase;

      final AuthenticatedUser user = await useCase.call(trimmedBarcode);

      // 2) сохраняем сессию
      WearSession.setUser(user);
      print('[AUTH] User authorized: ${user.name}');

      await WearFeedback.play(WearStatusKind.success);
      // 3) показываем статус — pop вернёт на WearMainScreen, тот push-нет меню
      state = state.copyWith(
        phase: WearAuthPhase.idle,
        nav: WearStatusScreenArgs(
          kind: WearStatusKind.success,
          title: 'Вошли как',
          message: user.name,
          autoAfter: const Duration(seconds: 2),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    } catch (error) {
      print('[AUTH] Authorization error: $error');
      await WearFeedback.play(WearStatusKind.error);
      state = state.copyWith(
        phase: WearAuthPhase.idle,
        nav: WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка входа',
          message: _asUiMessage(error),
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    }
  }

  Future<void> _authorizeWithMockUser() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    WearSession.setUser(_mockSkipUser);

    await WearFeedback.play(WearStatusKind.success);
    state = state.copyWith(
      phase: WearAuthPhase.idle,
      nav: WearStatusScreenArgs(
        kind: WearStatusKind.success,
        title: 'Вошли как',
        message: _mockSkipUser.name,
        autoAfter: const Duration(seconds: 2),
        autoAction: WearStatusAutoAction.pop,
      ),
    );
  }

  void consumeNavigation() {
    state = state.copyWith(clearNav: true);
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }

  bool _isMockLogoSkipAuthEnabled() {
    return dotenv.env['WEAR_MOCK_SKIP_AUTH_ON_LOGO'] == 'true';
  }

  Future<bool> _isAuthMockEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('WEAR_MOCK_AUTH') ?? false;
  }
}
