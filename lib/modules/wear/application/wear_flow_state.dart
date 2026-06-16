import 'package:smart_glasses/modules/wear/application/wear_navigation_request.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearFlowState {
  const WearFlowState({
    required this.screen,
    this.focusedIndex = 0,
    this.isLoading = false,
    this.error,
    this.pendingNavigation,
    this.menuFocusedIndex = 0,
    this.printerFocusedIndex = 0,
    this.productFocusedIndex = 0,
    this.availabilityInteractionFocusedIndex = 0,
    this.availabilityGroupFocusedIndex = 0,
    this.availabilityProductFocusedIndex = 0,
    this.availabilityDirectScanFocusedIndex = 0,
    this.availabilityFillFocusedIndex = 0,
    this.continueScanFocusedIndex = 0,
    this.currentPrinterSelection,
    this.currentProductSelectArgs,
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
  final int menuFocusedIndex;
  final int printerFocusedIndex;
  final int productFocusedIndex;
  final int availabilityInteractionFocusedIndex;
  final int availabilityGroupFocusedIndex;
  final int availabilityProductFocusedIndex;
  final int availabilityDirectScanFocusedIndex;
  final int availabilityFillFocusedIndex;
  final int continueScanFocusedIndex;
  final Object? currentPrinterSelection;
  final Object? currentProductSelectArgs;
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
    int? menuFocusedIndex,
    int? printerFocusedIndex,
    int? productFocusedIndex,
    int? availabilityInteractionFocusedIndex,
    int? availabilityGroupFocusedIndex,
    int? availabilityProductFocusedIndex,
    int? availabilityDirectScanFocusedIndex,
    int? availabilityFillFocusedIndex,
    int? continueScanFocusedIndex,
    Object? currentPrinterSelection,
    Object? currentProductSelectArgs,
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
      menuFocusedIndex: menuFocusedIndex ?? this.menuFocusedIndex,
      printerFocusedIndex: printerFocusedIndex ?? this.printerFocusedIndex,
      productFocusedIndex: productFocusedIndex ?? this.productFocusedIndex,
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
