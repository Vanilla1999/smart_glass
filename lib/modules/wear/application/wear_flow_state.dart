import 'package:smart_glasses/modules/wear/application/wear_navigation_request.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearFlowState {
  const WearFlowState({
    required this.screen,
    this.focusedIndex = 0,
    this.isLoading = false,
    this.error,
    this.pendingNavigation,
    this.homeConfirmReturnScreen = WearScreenId.menu,
    this.homeConfirmFocusedIndex = 0,
    this.menuFocusedIndex = 0,
    this.printerFocusedIndex = 0,
    this.productFocusedIndex = 0,
    this.voiceClarificationFocusedIndex = 0,
    this.availabilityInteractionFocusedIndex = 0,
    this.availabilityGroupFocusedIndex = 0,
    this.availabilityProductFocusedIndex = 0,
    this.availabilityDirectScanFocusedIndex = 0,
    this.availabilityFillFocusedIndex = 0,
    this.continueScanFocusedIndex = 0,
    this.currentPrinterSelection,
    this.currentProductSelectArgs,
    this.currentVoiceClarificationArgs,
    this.voiceClarificationNotice,
    this.currentAvailabilityGroup,
    this.currentAvailabilityProduct,
    this.currentStatusArgs,
  });

  factory WearFlowState.initial() {
    return const WearFlowState(screen: WearScreenId.scannerConnect);
  }

  final WearScreenId screen;
  final int focusedIndex;
  final bool isLoading;
  final String? error;
  final WearNavigationRequest? pendingNavigation;
  final WearScreenId homeConfirmReturnScreen;
  final int homeConfirmFocusedIndex;
  final int menuFocusedIndex;
  final int printerFocusedIndex;
  final int productFocusedIndex;
  final int voiceClarificationFocusedIndex;
  final int availabilityInteractionFocusedIndex;
  final int availabilityGroupFocusedIndex;
  final int availabilityProductFocusedIndex;
  final int availabilityDirectScanFocusedIndex;
  final int availabilityFillFocusedIndex;
  final int continueScanFocusedIndex;
  final Object? currentPrinterSelection;
  final Object? currentProductSelectArgs;
  final Object? currentVoiceClarificationArgs;
  final String? voiceClarificationNotice;
  final Object? currentAvailabilityGroup;
  final Object? currentAvailabilityProduct;
  final Object? currentStatusArgs;

  WearFlowState copyWith({
    WearScreenId? screen,
    int? focusedIndex,
    bool? isLoading,
    String? error,
    bool clearError = false,
    WearNavigationRequest? pendingNavigation,
    bool clearPendingNavigation = false,
    WearScreenId? homeConfirmReturnScreen,
    int? homeConfirmFocusedIndex,
    int? menuFocusedIndex,
    int? printerFocusedIndex,
    int? productFocusedIndex,
    int? voiceClarificationFocusedIndex,
    int? availabilityInteractionFocusedIndex,
    int? availabilityGroupFocusedIndex,
    int? availabilityProductFocusedIndex,
    int? availabilityDirectScanFocusedIndex,
    int? availabilityFillFocusedIndex,
    int? continueScanFocusedIndex,
    Object? currentPrinterSelection,
    Object? currentProductSelectArgs,
    Object? currentVoiceClarificationArgs,
    bool clearCurrentVoiceClarificationArgs = false,
    String? voiceClarificationNotice,
    bool clearVoiceClarificationNotice = false,
    Object? currentAvailabilityGroup,
    Object? currentAvailabilityProduct,
    Object? currentStatusArgs,
  }) {
    return WearFlowState(
      screen: screen ?? this.screen,
      focusedIndex: focusedIndex ?? this.focusedIndex,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      pendingNavigation: clearPendingNavigation
          ? null
          : pendingNavigation ?? this.pendingNavigation,
      homeConfirmReturnScreen:
          homeConfirmReturnScreen ?? this.homeConfirmReturnScreen,
      homeConfirmFocusedIndex:
          homeConfirmFocusedIndex ?? this.homeConfirmFocusedIndex,
      menuFocusedIndex: menuFocusedIndex ?? this.menuFocusedIndex,
      printerFocusedIndex: printerFocusedIndex ?? this.printerFocusedIndex,
      productFocusedIndex: productFocusedIndex ?? this.productFocusedIndex,
      voiceClarificationFocusedIndex:
          voiceClarificationFocusedIndex ?? this.voiceClarificationFocusedIndex,
      availabilityInteractionFocusedIndex:
          availabilityInteractionFocusedIndex ??
              this.availabilityInteractionFocusedIndex,
      availabilityGroupFocusedIndex:
          availabilityGroupFocusedIndex ?? this.availabilityGroupFocusedIndex,
      availabilityProductFocusedIndex: availabilityProductFocusedIndex ??
          this.availabilityProductFocusedIndex,
      availabilityDirectScanFocusedIndex: availabilityDirectScanFocusedIndex ??
          this.availabilityDirectScanFocusedIndex,
      availabilityFillFocusedIndex:
          availabilityFillFocusedIndex ?? this.availabilityFillFocusedIndex,
      continueScanFocusedIndex:
          continueScanFocusedIndex ?? this.continueScanFocusedIndex,
      currentPrinterSelection:
          currentPrinterSelection ?? this.currentPrinterSelection,
      currentProductSelectArgs:
          currentProductSelectArgs ?? this.currentProductSelectArgs,
      currentVoiceClarificationArgs: clearCurrentVoiceClarificationArgs
          ? null
          : currentVoiceClarificationArgs ?? this.currentVoiceClarificationArgs,
      voiceClarificationNotice: clearVoiceClarificationNotice
          ? null
          : voiceClarificationNotice ?? this.voiceClarificationNotice,
      currentAvailabilityGroup:
          currentAvailabilityGroup ?? this.currentAvailabilityGroup,
      currentAvailabilityProduct:
          currentAvailabilityProduct ?? this.currentAvailabilityProduct,
      currentStatusArgs: currentStatusArgs ?? this.currentStatusArgs,
    );
  }

  @override
  String toString() {
    return 'WearFlowState(screen: $screen, focusedIndex: $focusedIndex, '
        'menuFocusedIndex: $menuFocusedIndex, isLoading: $isLoading, '
        'error: $error, pendingNavigation: $pendingNavigation)';
  }
}
