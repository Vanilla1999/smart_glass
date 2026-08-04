import 'package:dio/dio.dart';
import 'package:smart_glasses/modules/wear/data/auth/data_source/auth_data_source.dart';
import 'package:smart_glasses/modules/wear/data/auth/data_source/auth_dio_client.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_actual_screen_store.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_catalog_fill_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/auth/use_case/authenticate_user_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_index_cache.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/free_text_pipeline_mode.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_typing_service.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/services/wear_photo_store.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime.dart';
import 'package:smart_glasses/modules/wear/services/wear_barcode_dispatcher.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';

// На следующих этапах пригодится, поэтому можно сразу оставить импорты
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_available_printers_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_barcode_info_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/print_price_tag_use_case.dart';

class WearDependencies {
  WearDependencies._() {
    _initVoiceServices();
  }

  static final WearDependencies I = WearDependencies._();

  // -------------------------
  // DBTO (Firebird) - один инстанс на все экраны
  // -------------------------
  final BdtoDataSource bdto = BdtoDataSource();

  /// Shared Vosk recognizer — один на digit‑dictation и voice‑commands.
  late final SpeechRecognitionService speechRecognitionService;

  late final VoiceTypingService voiceTypingService;

  late final WearVoiceControlService voiceControlService;
  late final VoiceActionCatalog voiceActionCatalog;
  late final VoiceHintIndexCache voiceHintIndexCache;

  late final WearFlowController wearFlowController;
  late final WearBarcodeDispatcher barcodeDispatcher;
  final WearActualScreenStore actualScreenStore = WearActualScreenStore();

  /// Shared audio stream — один на оба голосовых сервиса.
  late final AudioStreamService audioStreamService;

  void _initVoiceServices() {
    audioStreamService = AudioStreamService(
      recordContinuousWav: voiceCaptureWavDiagnostics,
    );
    wearFlowController = WearFlowController(
      glassesOutput: FlutterWearGlassesOutput(),
      navigationOutput: NoopWearNavigationOutput(),
      photoCapture: photoStore.captureLatestPhoto,
    );
    Future<void> navigate(
      WearScreenId screen, {
      Object? extra,
      bool replaceCurrent = false,
    }) {
      return wearFlowController.requestNavigation(
        screen,
        extra: extra,
        replaceCurrent: replaceCurrent,
      );
    }

    wearFlowController.setBackgroundRuntime(
      CompositeWearBackgroundRuntime(<WearBackgroundRuntime>[
        WearPrinterRuntime(
          loadPrinters: getAvailablePrintersUseCase().call,
          navigate: navigate,
        ),
        WearScanRuntime(
          lookupBarcode: getBarcodeInfoUseCase().call,
          navigate: navigate,
          currentScreen: () => wearFlowController.state.screen,
          printProduct: (BarcodeProductInfo product) async {
            final selection = WearSession.printerSelectionOrNull;
            final user = WearSession.userOrNull;
            if (selection == null) {
              throw StateError('Не выбраны принтеры');
            }
            if (user == null) {
              throw StateError('Пользователь не авторизован');
            }
            return printPriceTagUseCase.call(
              userId: user.idUser,
              employeeId: user.idEmployee,
              articleId: product.id,
              whiteTagsPrinterName: selection.whitePrinter.name,
              yellowTagsPrinterName: selection.yellowPrinter.name,
            );
          },
        ),
        WearAvailabilityRuntime(
          flowUseCase: availabilityFlowUseCase,
          navigate: navigate,
          capturePhoto: () async {
            await photoStore.captureLatestPhoto();
          },
          printPriceTag: (WearAvailabilityProduct product) async {
            final selection = WearSession.printerSelectionOrNull;
            final user = WearSession.userOrNull;
            if (selection == null) {
              throw StateError('Не выбраны принтеры');
            }
            if (user == null) {
              throw StateError('Пользователь не авторизован');
            }
            if (WearMockConfig.isEnabled) {
              return selection.whitePrinter.name;
            }
            return printPriceTagUseCase.call(
              userId: user.idUser,
              employeeId: user.idEmployee,
              articleId: product.id,
              whiteTagsPrinterName: selection.whitePrinter.name,
              yellowTagsPrinterName: selection.yellowPrinter.name,
            );
          },
        ),
      ]),
    );
    barcodeDispatcher = WearBarcodeDispatcher(
      flowController: wearFlowController,
    );
    voiceActionCatalog = VoiceActionCatalog(
      includeUnknown: const bool.fromEnvironment(
        'VOICE_GRAMMAR_INCLUDE_UNKNOWN',
        defaultValue: true,
      ),
      capabilities: VoiceScreenCapabilities(
        runtimeResolver: wearFlowController.canHandleVoiceCommand,
      ),
    );
    voiceHintIndexCache = VoiceHintIndexCache();
    WearGlassesVoiceHints.configureActionCatalog(voiceActionCatalog);
    WearGlassesVoiceHints.configureVoiceHintIndexCache(voiceHintIndexCache);
    speechRecognitionService = SpeechRecognitionService(
      audioStreamService: audioStreamService,
      commandGrammar: voiceActionCatalog.grammarFor(WearScreenId.menu),
      actionCatalog: voiceActionCatalog,
      dynamicItemsProvider: wearFlowController.dynamicVoiceItemsFor,
      voiceHintIndexCache: voiceHintIndexCache,
      freeTextPipelineMode: FreeTextPipelineMode.parse(
        dotenv.env['WEAR_FREE_TEXT_PIPELINE_MODE'],
      ),
    );
    voiceControlService = WearVoiceControlService(
      speechRecognitionService: speechRecognitionService,
      screenProvider: () => wearFlowController.state.screen,
      actionCatalog: voiceActionCatalog,
    );
    voiceTypingService = VoiceTypingService(
      speechRecognitionService: speechRecognitionService,
      audioStreamService: audioStreamService,
      resolvedPhrases: voiceControlService.phraseEventStream,
    );
    print(
      '[VoiceRuntime] freeTextMode=${dotenv.env['WEAR_FREE_TEXT_PIPELINE_MODE']} '
      'mocks=${WearMockConfig.isEnabled} '
      'wavDiagnostics=$voiceCaptureWavDiagnostics '
      'deviceProfile=${audioStreamService.deviceProfile.id} '
      'vadOn=${audioStreamService.deviceProfile.vadSpeechOnRms} '
      'vadOff=${audioStreamService.deviceProfile.vadSpeechOffRms} '
      'grammarSize=${voiceActionCatalog.grammarFor(WearScreenId.menu).length} '
      'audio=pcm16le/16000Hz/mono endpoint=vosk',
    );
  }

  final WearAvailabilityRepository availabilityRepository =
      LocalWearAvailabilityRepository();

  final WearPhotoStore photoStore = WearPhotoStore();
  final WearScannerRuntime scannerRuntime = WearScannerRuntime();

  late final WearAvailabilityFlowUseCase availabilityFlowUseCase =
      WearAvailabilityFlowUseCase(availabilityRepository);

  Future<void>? _voiceTypingPrepareFuture;

  // -------------------------
  // Auth use case - лениво создаем 1 раз
  // -------------------------
  Future<AuthenticateUserUseCase>? _authenticateUserUseCase;

  Future<AuthenticateUserUseCase> get authenticateUserUseCase async {
    return _authenticateUserUseCase ??= _createAuthenticateUserUseCase();
  }

  void resetAuthDependencies() {
    _authenticateUserUseCase = null;
  }

  Future<AuthenticateUserUseCase> _createAuthenticateUserUseCase() async {
    final Dio dio = await AuthDioClient().create();
    final AuthDataSource dataSource = AuthDataSource(dio);
    return AuthenticateUserUseCase(dataSource);
  }

  Future<void> ensureVoiceTypingPrepared() {
    final Future<void>? inFlight = _voiceTypingPrepareFuture;
    if (inFlight != null) {
      print('WearDependencies: VOSK warmup reused in-flight future');
      return inFlight;
    }

    print('WearDependencies: VOSK warmup start');
    final Future<void> prepareFuture = voiceTypingService.prepare();
    _voiceTypingPrepareFuture = prepareFuture.then<void>(
      (_) {
        print('WearDependencies: VOSK warmup done');
      },
      onError: (Object error, StackTrace stackTrace) {
        _voiceTypingPrepareFuture = null;
        print('WearDependencies: VOSK warmup error: $error\n$stackTrace');
        throw Exception(error.toString());
      },
    );

    return _voiceTypingPrepareFuture!;
  }

  Future<void> disposeVoiceServices() async {
    _voiceTypingPrepareFuture = null;
    await speechRecognitionService.dispose();
  }

  // -------------------------
  // На следующий этап (принтеры/печать)
  // -------------------------
  GetAvailablePrintersUseCase getAvailablePrintersUseCase() =>
      GetAvailablePrintersUseCase(bdto);

  GetBarcodeInfoUseCase getBarcodeInfoUseCase() => GetBarcodeInfoUseCase(bdto);

  WearAvailabilityCatalogFillUseCase availabilityCatalogFillUseCase() =>
      WearAvailabilityCatalogFillUseCase(
        getBarcodeInfoUseCase: getBarcodeInfoUseCase(),
        repository: availabilityRepository,
      );

  PrintPriceTagUseCase get printPriceTagUseCase => PrintPriceTagUseCase(bdto);
}
