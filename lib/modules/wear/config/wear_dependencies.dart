import 'package:dio/dio.dart';
import 'package:smart_glasses/modules/wear/data/auth/data_source/auth_data_source.dart';
import 'package:smart_glasses/modules/wear/data/auth/data_source/auth_dio_client.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_catalog_fill_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/auth/use_case/authenticate_user_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_typing_service.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';

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

  late final WearFlowController wearFlowController;

  /// Shared audio stream — один на оба голосовых сервиса.
  late final AudioStreamService audioStreamService;

  void _initVoiceServices() {
    audioStreamService = AudioStreamService();
    speechRecognitionService = SpeechRecognitionService(
      audioStreamService: audioStreamService,
    );
    voiceTypingService = VoiceTypingService(
      speechRecognitionService: speechRecognitionService,
      audioStreamService: audioStreamService,
    );
    voiceControlService = WearVoiceControlService(
      speechRecognitionService: speechRecognitionService,
    );
    wearFlowController = WearFlowController(
      glassesOutput: FlutterWearGlassesOutput(),
      navigationOutput: NoopWearNavigationOutput(),
    );
  }

  final WearAvailabilityRepository availabilityRepository =
      LocalWearAvailabilityRepository();

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

  void warmupVoiceTypingInBackground() {
    ensureVoiceTypingPrepared().catchError((Object error, StackTrace _) {
      print('WearDependencies: VOSK warmup failed: $error');
    });
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
