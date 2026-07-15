import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/cubit/wear_availability_list_providers.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_product_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityGroupScreen extends ConsumerStatefulWidget {
  const WearAvailabilityGroupScreen({super.key});

  static const String route = '/wear_availability_groups';

  @override
  ConsumerState<WearAvailabilityGroupScreen> createState() =>
      _WearAvailabilityGroupScreenState();
}

class _WearAvailabilityGroupScreenState
    extends ConsumerState<WearAvailabilityGroupScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(
      WearScreenId.availabilityGroup,
    );
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.availabilityGroup,
      WearScreenActionHandler(
        onUp: _onVoiceUp,
        onDown: _onVoiceDown,
        onSelect: _onVoiceSelect,
        onNextPage: _onVoiceNextPage,
        onPreviousPage: _onVoicePreviousPage,
        onPhrase: _onVoicePhrase,
        onPartialPhrase: _onVoicePartialPhrase,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final List<WearAvailabilityGroup>? groups =
          ref.read(wearAvailabilityGroupsProvider).valueOrNull;
      if (groups == null) return;
      _sendGlassesState(groups, fast: true);
    });
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.availabilityGroup,
    );
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<WearAvailabilityGroup>> groups =
        ref.watch(wearAvailabilityGroupsProvider);
    groups.whenData(_sendGlassesState);

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: groups.when(
        data: _buildGroups,
        loading: () {
          _sendLoading();
          return const Center(child: WearLoading());
        },
        error: (Object error, StackTrace _) {
          _sendError(error);
          return _buildMessage('Ошибка загрузки\n${_asUiMessage(error)}');
        },
      ),
    );
  }

  Widget _buildGroups(List<WearAvailabilityGroup> groups) {
    if (groups.isEmpty) {
      return _buildMessage('Нет заданий доступности');
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(wearAvailabilityGroupsProvider.future),
      child: WearScalingListView(
        controller: _scroll,
        itemCount: groups.length + 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                'Доступность',
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }
          if (i == groups.length + 1) {
            return const SizedBox.shrink();
          }

          final WearAvailabilityGroup group = groups[i - 1];
          return WearPill(
            title: group.name,
            subtitle: 'ТП: ${group.counter}',
            icon: WearImages.database,
            onTap: () => context.push(
              WearAvailabilityProductScreen.route,
              extra: group,
            ),
          );
        },
        onFocusChanged: (int listIndex) {
          final int itemIndex = (listIndex - 1).clamp(0, groups.length - 1);
          if (itemIndex == _focusedIndex) return;
          _focusedIndex = itemIndex;
          _sendGlassesState(groups, fast: true);
        },
      ),
    );
  }

  void _onVoiceUp() {
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, groups.length - 1);
    if (_focusedIndex <= 0) return;
    _focusedIndex--;
    _scrollToFocused();
    _sendGlassesState(groups, fast: true);
  }

  void _onVoiceDown() {
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, groups.length - 1);
    if (_focusedIndex >= groups.length - 1) return;
    _focusedIndex++;
    _scrollToFocused();
    _sendGlassesState(groups, fast: true);
  }

  void _onVoiceSelect() {
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return;
    final int groupIndex = _focusedIndex.clamp(0, groups.length - 1);
    context.push(WearAvailabilityProductScreen.route,
        extra: groups[groupIndex]);
  }

  void _onVoiceNextPage() {
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    final int nextIndex = (currentPage + 1) * _visibleGlassesItemCount;
    if (nextIndex >= groups.length) {
      _showVoiceSearchMessage('Это последняя страница');
      return;
    }
    _focusedIndex = nextIndex.clamp(0, groups.length - 1);
    _scrollToFocused();
    _sendGlassesState(groups, fast: true);
  }

  void _onVoicePreviousPage() {
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    if (currentPage == 0) {
      _showVoiceSearchMessage('Это первая страница');
      return;
    }
    final int previousIndex = (currentPage - 1) * _visibleGlassesItemCount;
    _focusedIndex = previousIndex.clamp(0, groups.length - 1);
    _scrollToFocused();
    _sendGlassesState(groups, fast: true);
  }

  void _onVoicePhrase(String phrase) {
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return;
    final VoiceListMatch<WearAvailabilityGroup> match = VoiceListMatcher.match(
      phrase,
      groups,
      (WearAvailabilityGroup group) => group.name,
    );
    switch (match.type) {
      case VoiceListMatchType.none:
        _showVoiceSearchMessage('Не найдено');
        break;
      case VoiceListMatchType.ambiguous:
        _showVoiceSearchMessage('Назовите точнее');
        break;
      case VoiceListMatchType.unique:
        final WearAvailabilityGroup group = match.item!;
        final int index = groups.indexWhere((WearAvailabilityGroup item) {
          return item.id == group.id;
        });
        if (index >= 0) {
          _focusedIndex = index;
          _scrollToFocused();
          _sendGlassesState(groups, fast: true);
        }
        context.push(WearAvailabilityProductScreen.route, extra: group);
        break;
    }
  }

  bool _onVoicePartialPhrase(String phrase) {
    if (!VoiceListMatcher.canMatchPartial(phrase)) return false;
    final List<WearAvailabilityGroup>? groups =
        ref.read(wearAvailabilityGroupsProvider).valueOrNull;
    if (groups == null || groups.isEmpty) return false;
    final VoiceListMatch<WearAvailabilityGroup> match = VoiceListMatcher.match(
      phrase,
      groups,
      (WearAvailabilityGroup group) => group.name,
    );
    if (match.type != VoiceListMatchType.unique) {
      return false;
    }

    final WearAvailabilityGroup group = match.item!;
    final int index = groups.indexWhere((WearAvailabilityGroup item) {
      return item.id == group.id;
    });
    if (index >= 0) {
      _focusedIndex = index;
      _scrollToFocused();
      _sendGlassesState(groups, fast: true);
    }
    return false;
  }

  void _scrollToFocused() {
    if (!_scroll.hasClients) return;
    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Text(
        message,
        style: WearTypography.lable,
        textAlign: TextAlign.center,
      ),
    );
  }

  void _sendGlassesState(
    List<WearAvailabilityGroup> groups, {
    bool fast = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final payload = WearAvailabilityGlassesPayloads.groups(
        groups,
        selectedIndex: _focusedIndex,
      );
      WearDependencies.I.wearFlowController.rememberScreenPayload(
        WearScreenId.availabilityGroup,
        payload,
      );
      if (fast) {
        WearStatusIconReporter.I.sendFastForScreen(
          WearScreenId.availabilityGroup,
          payload,
        );
      } else {
        WearStatusIconReporter.I.sendForScreen(
          WearScreenId.availabilityGroup,
          payload,
        );
      }
    });
  }

  void _sendLoading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.sendForScreen(
        WearScreenId.availabilityGroup,
        WearAvailabilityGlassesPayloads.loading(
          title: 'Доступность',
          statusText: 'Загружаем...',
          statusIcon: WearImages.database,
        ),
      );
    });
  }

  void _sendError(Object error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.sendForScreen(
        WearScreenId.availabilityGroup,
        WearAvailabilityGlassesPayloads.error(
          title: 'Ошибка доступности',
          message: _asUiMessage(error),
        ),
      );
    });
  }

  void _showVoiceSearchMessage(String message) {
    WearStatusIconReporter.I.showTransientFastForScreen(
      WearScreenId.availabilityGroup,
      WearGlassesPayload.status(
        isError: true,
        title: 'Голосовой выбор',
        statusText: message,
      ),
    );
  }

  static const int _visibleGlassesItemCount = 4;

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
