import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearVoiceClarificationScreen extends StatefulWidget {
  const WearVoiceClarificationScreen({super.key, required this.args});

  static const String route = '/wear_voice_clarification';

  final VoiceClarificationArgs? args;

  @override
  State<WearVoiceClarificationScreen> createState() =>
      _WearVoiceClarificationScreenState();
}

class _WearVoiceClarificationScreenState
    extends State<WearVoiceClarificationScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  bool _isSelecting = false;
  String? _notice;
  Timer? _noticeTimer;
  VoiceClarificationArgs? _currentArgs;

  WearFlowController get _flow => WearDependencies.I.wearFlowController;

  List<VoiceDynamicItem> get _matches =>
      _currentArgs?.matches ?? const <VoiceDynamicItem>[];

  @override
  void initState() {
    super.initState();
    _currentArgs = widget.args;
    _flow.enterScreen(
      WearScreenId.voiceClarification,
      extra: _currentArgs,
    );
    _flow.registerScreenActions(
      WearScreenId.voiceClarification,
      WearScreenActionHandler(
        onUp: _onUp,
        onDown: _onDown,
        onSelect: _onSelect,
        onBack: _onBack,
        onPhrase: _onPhrase,
        dynamicVoiceItems: _dynamicVoiceItems,
      ),
    );
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _flow.unregisterScreenActions(WearScreenId.voiceClarification);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_matches.isEmpty) {
      return _withBackHistory(WearScreenScaffold(
        showHomeButton: true,
        child: Center(
          child: Text(
            'Совпадения не найдены',
            style: WearTypography.lable,
            textAlign: TextAlign.center,
          ),
        ),
      ));
    }

    return _withBackHistory(WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: _matches.length + 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        physics: const ClampingScrollPhysics(),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                'Уточните фразу',
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }
          if (index == _matches.length + 1) {
            return const SizedBox.shrink();
          }
          final VoiceDynamicItem item = _matches[index - 1];
          return WearPill(
            title: item.label,
            onTap: () => _select(item),
          );
        },
        onFocusChanged: (int listIndex) {
          final int next = (listIndex - 1).clamp(0, _matches.length - 1);
          if (next == _focusedIndex) return;
          _focusedIndex = next;
          _flow.setVoiceClarificationFocusedIndex(next, _matches.length);
        },
      ),
    ));
  }

  Widget _withBackHistory(Widget child) {
    return PopScope<Object?>(
      canPop: _currentArgs?.previous == null,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _restorePreviousClarification();
        }
      },
      child: Stack(
        children: <Widget>[
          child,
          if (_notice != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 8,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WearColors.textDefault,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        _notice!,
                        style: WearTypography.bodyxsm.copyWith(
                          color: WearColors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  VoiceDynamicItemsSnapshot _dynamicVoiceItems() {
    return VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        _matches.map(
          (VoiceDynamicItem item) => Object.hash(item.id, item.label),
        ),
      ),
      items: _matches,
    );
  }

  void _onUp() {
    if (_focusedIndex <= 0) return;
    _focusedIndex--;
    _focusCurrent();
  }

  void _onDown() {
    if (_focusedIndex >= _matches.length - 1) return;
    _focusedIndex++;
    _focusCurrent();
  }

  Future<void> _onSelect() async {
    if (_matches.isEmpty) return;
    await _select(_matches[_focusedIndex.clamp(0, _matches.length - 1)]);
  }

  Future<void> _onPhrase(String phrase) async {
    final VoiceListMatch<VoiceDynamicItem> match = VoiceListMatcher.match(
      phrase,
      _matches,
      (VoiceDynamicItem item) => item.label,
    );
    switch (match.type) {
      case VoiceListMatchType.none:
        _showNotice('Совпадений нет');
        return;
      case VoiceListMatchType.ambiguous:
        if (match.matches.length >= _matches.length) {
          _showNotice('Назовите точнее');
          return;
        }
        final VoiceClarificationArgs current = _currentArgs!;
        final VoiceClarificationArgs next = VoiceClarificationArgs(
          sourceScreen: current.sourceScreen,
          phrase: phrase.trim(),
          matches: match.matches,
          previous: current,
        );
        setState(() {
          _currentArgs = next;
          _focusedIndex = 0;
          _notice = null;
        });
        _clearNotice();
        _flow.enterScreen(WearScreenId.voiceClarification, extra: next);
        _focusCurrent();
        return;
      case VoiceListMatchType.unique:
        await _select(match.item!);
    }
  }

  Future<void> _select(VoiceDynamicItem item) async {
    final VoiceClarificationArgs? args = _currentArgs;
    if (args == null || _isSelecting) return;
    setState(() {
      _isSelecting = true;
      _notice = null;
    });
    _clearNotice();
    final bool selected =
        await _flow.selectVoiceClarificationItem(args, item.id);
    if (!selected && mounted) {
      setState(() => _isSelecting = false);
      _showNotice('Список изменился');
    }
  }

  void _onBack() {
    if (_restorePreviousClarification()) return;
    context.pop();
  }

  bool _restorePreviousClarification() {
    final VoiceClarificationArgs? previous = _currentArgs?.previous;
    if (previous == null) return false;
    setState(() {
      _currentArgs = previous;
      _focusedIndex = 0;
      _notice = null;
      _isSelecting = false;
    });
    _clearNotice();
    _flow.enterScreen(WearScreenId.voiceClarification, extra: previous);
    _focusCurrent();
    return true;
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _flow.setVoiceClarificationNotice(message);
    _noticeTimer = Timer(const Duration(seconds: 2), _clearNotice);
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    if (mounted && _notice != null) {
      setState(() => _notice = null);
    }
    _flow.setVoiceClarificationNotice(null);
  }

  void _focusCurrent() {
    _flow.setVoiceClarificationFocusedIndex(_focusedIndex, _matches.length);
    if (!_scroll.hasClients) return;
    final double target = ((_focusedIndex + 1) * 56.0)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }
}
