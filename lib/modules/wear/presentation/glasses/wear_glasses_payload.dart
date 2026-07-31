enum WearGlassesScreenType {
  auth,
  menu,
  printer,
  scan,
  productSelect,
  availability,
  printing,
  status,
  help,
  continueScan,
}

enum WearGlassesPhase {
  idle,
  loading,
  scanning,
  recognizing,
  success,
  error,
}

class WearGlassesVoiceHint {
  const WearGlassesVoiceHint({
    required this.itemId,
    required this.phrase,
    required this.start,
    required this.end,
  });

  factory WearGlassesVoiceHint.fromJson(Map<dynamic, dynamic> json) {
    return WearGlassesVoiceHint(
      itemId: json['itemId']?.toString() ?? '',
      phrase: json['phrase']?.toString() ?? '',
      start: _parseInt(json['start']),
      end: _parseInt(json['end']),
    );
  }

  final String itemId;
  final String phrase;
  final int start;
  final int end;

  bool isValidFor(String label) =>
      start >= 0 && end > start && end <= label.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'itemId': itemId,
        'phrase': phrase,
        'start': start,
        'end': end,
      };

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class WearGlassesPayload {
  const WearGlassesPayload({
    required this.screenType,
    required this.phase,
    required this.title,
    this.subtitle,
    this.statusText,
    this.isLoading = false,
    this.isError = false,
    this.items = const <String>[],
    this.voiceHints = const <WearGlassesVoiceHint>[],
    this.bodyLines = const <String>[],
    this.checkLines = const <String>[],
    this.selectedIndex = 0,
    this.pageText,
    this.footerText,
    this.primaryAction,
    this.secondaryAction,
    this.statusIcon,
    this.showWifiIcon = true,
    this.wifiAvailable = false,
    this.wifiLevel = 3,
    this.showPrinterIcon = false,
    this.printerAvailable = false,
    this.voiceCommandsEnabled = true,
    this.performanceTraceId,
    this.performanceCommand,
    this.performanceRecognizedAtMillis,
    this.performanceAsrMillis,
    this.performanceSentAtMillis,
  });

  factory WearGlassesPayload.authWaitingBarcode() {
    return const WearGlassesPayload(
      screenType: WearGlassesScreenType.auth,
      phase: WearGlassesPhase.scanning,
      title: 'Авторизация',
      subtitle: 'Наведите камеру на штрих-код',
      statusText: 'Поиск ШК...',
    );
  }

  factory WearGlassesPayload.authLoading() {
    return const WearGlassesPayload(
      screenType: WearGlassesScreenType.auth,
      phase: WearGlassesPhase.loading,
      title: 'Авторизация',
      statusText: 'Авторизуемся...',
      isLoading: true,
    );
  }

  factory WearGlassesPayload.authSuccess(String userName) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.auth,
      phase: WearGlassesPhase.success,
      title: 'Авторизация',
      statusText: 'Успешно',
    );
  }

  factory WearGlassesPayload.menu({int selectedIndex = 0}) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.menu,
      phase: WearGlassesPhase.idle,
      title: 'Выбор раздела',
      items: const <String>[
        'Печать ценников',
        'Доступность',
        'Справка',
        'Настройки',
      ],
      selectedIndex: selectedIndex,
    );
  }

  factory WearGlassesPayload.continueScan({int selectedIndex = 0}) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.continueScan,
      phase: WearGlassesPhase.idle,
      title: 'Сканирование товара',
      subtitle: 'Готовы продолжить?',
      items: const <String>['Продолжить', 'Завершить'],
      selectedIndex: selectedIndex,
      primaryAction: 'Продолжить',
      secondaryAction: 'Завершить',
    );
  }

  factory WearGlassesPayload.homeConfirm({int selectedIndex = 0}) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.menu,
      phase: WearGlassesPhase.idle,
      title: 'Вернуться домой',
      subtitle: 'Домой - в меню после авторизации',
      items: const <String>['Домой', 'Отмена'],
      selectedIndex: selectedIndex,
      primaryAction: 'Домой',
      secondaryAction: 'Отмена',
    );
  }

  factory WearGlassesPayload.help() {
    return const WearGlassesPayload(
      screenType: WearGlassesScreenType.help,
      phase: WearGlassesPhase.idle,
      showWifiIcon: false,
      title: 'Справка',
      items: <String>[
        'Дистанция сканирования: до 50 см',
        'Голосовые команды:\n«Вверх», «Вниз», «Выбрать», «Назад», «Домой»',
        'Кнопки:\n↑ - Вверх, ↓ - Вниз, Ок - Выбрать,\nУдержание Ок - Домой, Удержание ↓ - Назад',
      ],
      primaryAction: 'Начать работу',
    );
  }

  factory WearGlassesPayload.scanWaiting() {
    return const WearGlassesPayload(
      screenType: WearGlassesScreenType.scan,
      phase: WearGlassesPhase.scanning,
      title: 'Сканирование',
      subtitle: 'Наведите камеру на штрих-код',
      statusText: 'Поиск ШК...',
    );
  }

  factory WearGlassesPayload.scanLoading() {
    return const WearGlassesPayload(
      screenType: WearGlassesScreenType.scan,
      phase: WearGlassesPhase.loading,
      title: 'Сканирование',
      statusText: 'ШК отсканирован, распознаю...',
      isLoading: true,
    );
  }

  factory WearGlassesPayload.loading({
    required WearGlassesScreenType screenType,
    required String title,
    required String statusText,
    String? subtitle,
    String? statusIcon,
  }) {
    return WearGlassesPayload(
      screenType: screenType,
      phase: WearGlassesPhase.loading,
      title: title,
      subtitle: subtitle,
      statusText: statusText,
      isLoading: true,
      statusIcon: statusIcon,
    );
  }

  factory WearGlassesPayload.printing({
    String? productName,
    String? statusIcon,
  }) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.printing,
      phase: WearGlassesPhase.loading,
      title: 'Печать ценника',
      subtitle: productName,
      statusText: 'Отправляем на печать...',
      statusIcon: statusIcon,
      isLoading: true,
    );
  }

  factory WearGlassesPayload.status({
    required bool isError,
    required String title,
    String? subtitle,
    String? statusText,
    String? statusIcon,
  }) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.status,
      phase: isError ? WearGlassesPhase.error : WearGlassesPhase.success,
      title: title,
      subtitle: subtitle,
      statusText: statusText,
      isError: isError,
      statusIcon: statusIcon,
    );
  }

  final WearGlassesScreenType screenType;
  final WearGlassesPhase phase;
  final String title;
  final String? subtitle;
  final String? statusText;
  final bool isLoading;
  final bool isError;
  final List<String> items;
  final List<WearGlassesVoiceHint> voiceHints;
  final List<String> bodyLines;
  final List<String> checkLines;
  final int selectedIndex;
  final String? pageText;
  final String? footerText;
  final String? primaryAction;
  final String? secondaryAction;
  final String? statusIcon;
  final bool showWifiIcon;
  final bool wifiAvailable;
  final int wifiLevel;
  final bool showPrinterIcon;
  final bool printerAvailable;
  final bool voiceCommandsEnabled;
  final String? performanceTraceId;
  final String? performanceCommand;
  final int? performanceRecognizedAtMillis;
  final int? performanceAsrMillis;
  final int? performanceSentAtMillis;

  WearGlassesPayload copyWithStatusIcons({
    bool? showWifiIcon,
    bool? wifiAvailable,
    int? wifiLevel,
    bool? showPrinterIcon,
    bool? printerAvailable,
    bool? voiceCommandsEnabled,
  }) {
    return WearGlassesPayload(
      screenType: screenType,
      phase: phase,
      title: title,
      subtitle: subtitle,
      statusText: statusText,
      isLoading: isLoading,
      isError: isError,
      items: items,
      voiceHints: voiceHints,
      bodyLines: bodyLines,
      checkLines: checkLines,
      selectedIndex: selectedIndex,
      pageText: pageText,
      footerText: footerText,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      statusIcon: statusIcon,
      showWifiIcon: showWifiIcon ?? this.showWifiIcon,
      wifiAvailable: wifiAvailable ?? this.wifiAvailable,
      wifiLevel: wifiLevel ?? this.wifiLevel,
      showPrinterIcon: showPrinterIcon ?? this.showPrinterIcon,
      printerAvailable: printerAvailable ?? this.printerAvailable,
      voiceCommandsEnabled: voiceCommandsEnabled ?? this.voiceCommandsEnabled,
      performanceTraceId: performanceTraceId,
      performanceCommand: performanceCommand,
      performanceRecognizedAtMillis: performanceRecognizedAtMillis,
      performanceAsrMillis: performanceAsrMillis,
      performanceSentAtMillis: performanceSentAtMillis,
    );
  }

  WearGlassesPayload copyWithPerformanceTrace({
    required String traceId,
    required String command,
    required int recognizedAtMillis,
    required int asrMillis,
    required int sentAtMillis,
  }) {
    return WearGlassesPayload(
      screenType: screenType,
      phase: phase,
      title: title,
      subtitle: subtitle,
      statusText: statusText,
      isLoading: isLoading,
      isError: isError,
      items: items,
      voiceHints: voiceHints,
      bodyLines: bodyLines,
      checkLines: checkLines,
      selectedIndex: selectedIndex,
      pageText: pageText,
      footerText: footerText,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      statusIcon: statusIcon,
      showWifiIcon: showWifiIcon,
      wifiAvailable: wifiAvailable,
      wifiLevel: wifiLevel,
      showPrinterIcon: showPrinterIcon,
      printerAvailable: printerAvailable,
      voiceCommandsEnabled: voiceCommandsEnabled,
      performanceTraceId: traceId,
      performanceCommand: command,
      performanceRecognizedAtMillis: recognizedAtMillis,
      performanceAsrMillis: asrMillis,
      performanceSentAtMillis: sentAtMillis,
    );
  }

  WearGlassesPayload copyWithStatusText(String? value) {
    return WearGlassesPayload(
      screenType: screenType,
      phase: phase,
      title: title,
      subtitle: subtitle,
      statusText: value,
      isLoading: isLoading,
      isError: isError,
      items: items,
      voiceHints: voiceHints,
      bodyLines: bodyLines,
      checkLines: checkLines,
      selectedIndex: selectedIndex,
      pageText: pageText,
      footerText: footerText,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      statusIcon: statusIcon,
      showWifiIcon: showWifiIcon,
      wifiAvailable: wifiAvailable,
      wifiLevel: wifiLevel,
      showPrinterIcon: showPrinterIcon,
      printerAvailable: printerAvailable,
      voiceCommandsEnabled: voiceCommandsEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'screenType': screenType.name,
      'phase': phase.name,
      'title': title,
      'subtitle': subtitle,
      'statusText': statusText,
      'isLoading': isLoading,
      'isError': isError,
      'items': items,
      'voiceHints': voiceHints
          .map((WearGlassesVoiceHint hint) => hint.toJson())
          .toList(growable: false),
      'bodyLines': bodyLines,
      'checkLines': checkLines,
      'selectedIndex': selectedIndex,
      'pageText': pageText,
      'footerText': footerText,
      'primaryAction': primaryAction,
      'secondaryAction': secondaryAction,
      'statusIcon': statusIcon,
      'showWifiIcon': showWifiIcon,
      'wifiAvailable': wifiAvailable,
      'wifiLevel': wifiLevel,
      'showPrinterIcon': showPrinterIcon,
      'printerAvailable': printerAvailable,
      'voiceCommandsEnabled': voiceCommandsEnabled,
      'performanceTraceId': performanceTraceId,
      'performanceCommand': performanceCommand,
      'performanceRecognizedAtMillis': performanceRecognizedAtMillis,
      'performanceAsrMillis': performanceAsrMillis,
      'performanceSentAtMillis': performanceSentAtMillis,
    };
  }
}
