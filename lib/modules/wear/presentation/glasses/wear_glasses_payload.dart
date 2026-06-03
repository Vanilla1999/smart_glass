enum WearGlassesScreenType {
  auth,
  menu,
  printer,
  scan,
  productSelect,
  printing,
  status,
  help,
}

enum WearGlassesPhase {
  idle,
  loading,
  scanning,
  recognizing,
  success,
  error,
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
    this.selectedIndex = 0,
    this.pageText,
    this.primaryAction,
    this.secondaryAction,
    this.statusIcon,
    this.showWifiIcon = true,
    this.wifiAvailable = false,
    this.wifiLevel = 3,
    this.showPrinterIcon = false,
    this.printerAvailable = false,
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

  factory WearGlassesPayload.menu() {
    return const WearGlassesPayload(
      screenType: WearGlassesScreenType.menu,
      phase: WearGlassesPhase.idle,
      title: 'Выбор раздела',
      items: <String>['Печать ценников', 'Доступность', 'Справка'],
      selectedIndex: 0,
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

  factory WearGlassesPayload.printing({String? productName}) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.printing,
      phase: WearGlassesPhase.loading,
      title: 'Печать ценника',
      subtitle: productName,
      statusText: 'Отправляем на печать...',
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
  final int selectedIndex;
  final String? pageText;
  final String? primaryAction;
  final String? secondaryAction;
  final String? statusIcon;
  final bool showWifiIcon;
  final bool wifiAvailable;
  final int wifiLevel;
  final bool showPrinterIcon;
  final bool printerAvailable;

  WearGlassesPayload copyWithStatusIcons({
    bool? showWifiIcon,
    bool? wifiAvailable,
    int? wifiLevel,
    bool? showPrinterIcon,
    bool? printerAvailable,
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
      selectedIndex: selectedIndex,
      pageText: pageText,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      statusIcon: statusIcon,
      showWifiIcon: showWifiIcon ?? this.showWifiIcon,
      wifiAvailable: wifiAvailable ?? this.wifiAvailable,
      wifiLevel: wifiLevel ?? this.wifiLevel,
      showPrinterIcon: showPrinterIcon ?? this.showPrinterIcon,
      printerAvailable: printerAvailable ?? this.printerAvailable,
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
      'selectedIndex': selectedIndex,
      'pageText': pageText,
      'primaryAction': primaryAction,
      'secondaryAction': secondaryAction,
      'statusIcon': statusIcon,
      'showWifiIcon': showWifiIcon,
      'wifiAvailable': wifiAvailable,
      'wifiLevel': wifiLevel,
      'showPrinterIcon': showPrinterIcon,
      'printerAvailable': printerAvailable,
    };
  }
}
