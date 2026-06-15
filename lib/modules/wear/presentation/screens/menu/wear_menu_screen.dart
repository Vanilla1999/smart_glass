import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/help/wear_help_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_voice_command_listener.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearMenuScreen extends StatefulWidget {
  const WearMenuScreen({super.key});

  static const String route = '/wear_menu';

  @override
  State<WearMenuScreen> createState() => _WearMenuScreenState();
}

class _WearMenuScreenState extends State<WearMenuScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  static const int _menuItemCount = 4;

  @override
  void initState() {
    super.initState();
    _focusedIndex = 0; // Сбрасываем при входе на экран
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendMenuPayload();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onVoiceUp() {
    print('[MenuScreen] ========== _onVoiceUp START ==========');
    print('[MenuScreen] _onVoiceUp called, _focusedIndex=$_focusedIndex');
    if (!_scroll.hasClients) {
      print('[MenuScreen] no scroll clients, aborting');
      return;
    }
    if (_focusedIndex <= 0) {
      print(
        '[MenuScreen] already at top, _focusedIndex=$_focusedIndex, aborting',
      );
      return;
    }
    _focusedIndex = _focusedIndex - 1;
    print('[MenuScreen] _focusedIndex decremented to: $_focusedIndex');
    print(
      '[MenuScreen] MENU: [0]=Печать ценника, [1]=Доступность, [2]=Справка, [3]=Настройки',
    );
    print('[MenuScreen] will navigate to: ${_getMenuItemName(_focusedIndex)}');

    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    print('[MenuScreen] scrolling to offset: $target');
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    WearStatusIconReporter.I.sendFast(
      WearGlassesPayload.menu(selectedIndex: _focusedIndex),
    );
    print('[MenuScreen] ========== _onVoiceUp END ==========');
  }

  void _onVoiceDown() {
    print('[MenuScreen] ========== _onVoiceDown START ==========');
    print('[MenuScreen] _onVoiceDown called, _focusedIndex=$_focusedIndex');
    if (!_scroll.hasClients) {
      print('[MenuScreen] no scroll clients, aborting');
      return;
    }
    if (_focusedIndex >= _menuItemCount - 1) {
      print(
        '[MenuScreen] already at bottom (_menuItemCount=$_menuItemCount), _focusedIndex=$_focusedIndex, aborting',
      );
      return;
    }
    _focusedIndex = _focusedIndex + 1;
    print('[MenuScreen] _focusedIndex incremented to: $_focusedIndex');
    print(
      '[MenuScreen] MENU: [0]=Печать ценника, [1]=Доступность, [2]=Справка, [3]=Настройки',
    );
    print('[MenuScreen] will navigate to: ${_getMenuItemName(_focusedIndex)}');

    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    print('[MenuScreen] scrolling to offset: $target');
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    WearStatusIconReporter.I.sendFast(
      WearGlassesPayload.menu(selectedIndex: _focusedIndex),
    );
    print('[MenuScreen] ========== _onVoiceDown END ==========');
  }

  String _getMenuItemName(int index) {
    switch (index) {
      case 0:
        return 'Печать ценника';
      case 1:
        return 'Доступность';
      case 2:
        return 'Справка';
      case 3:
        return 'Настройки';
      default:
        return 'UNKNOWN(index=$index)';
    }
  }

  void _sendMenuPayload() {
    WearStatusIconReporter.I.send(
      WearGlassesPayload.menu(selectedIndex: _focusedIndex),
    );
  }

  Future<void> _pushAndRefreshMenu(String route) async {
    await context.push(route);
    if (!mounted) return;
    _sendMenuPayload();
  }

  void _onVoiceSelect() {
    print('[MenuScreen] ========== _onVoiceSelect START ==========');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    print('[MenuScreen] _onVoiceSelect called');
    print('[MenuScreen] _focusedIndex=$_focusedIndex (это индекс меню очков)');
    print(
      '[MenuScreen] MENU_ITEMS: [0]=Печать ценника, [1]=Доступность, [2]=Справка, [3]=Настройки',
    );
    print('[MenuScreen] selected item: ${_getMenuItemName(_focusedIndex)}');

    if (!_scroll.hasClients) {
      print('[MenuScreen] _onVoiceSelect: scroll has no clients, aborting');
      return;
    }

    final int listIndex = _focusedListIndex();
    print('[MenuScreen] _focusedListIndex() returned: listIndex=$listIndex');
    print(
      '[MenuScreen] WIDGETS: [0]=Меню, [1]=Печать, [2]=Доступность, [3]=Справка, [4]=Настройки, [5]=Spacer',
    );

    // Выбираем на основе _focusedIndex (который обновляется через onFocusChanged)
    print('[MenuScreen] USING _focusedIndex for navigation');
    if (_focusedIndex == 0) {
      print('[MenuScreen] NAVIGATING TO: WearPrinterSelectScreen');
      final t1 = DateTime.now().millisecondsSinceEpoch;
      print('[MenuScreen] LATENCY: voice->action: ${t1 - t0}ms');
      _pushAndRefreshMenu(WearPrinterSelectScreen.route);
    } else if (_focusedIndex == 1) {
      print('[MenuScreen] NAVIGATING TO: WearAvailabilityInteractionScreen');
      final t1 = DateTime.now().millisecondsSinceEpoch;
      print('[MenuScreen] LATENCY: voice->action: ${t1 - t0}ms');
      _pushAndRefreshMenu(WearAvailabilityInteractionScreen.route);
    } else if (_focusedIndex == 2) {
      print('[MenuScreen] NAVIGATING TO: WearHelpScreen');
      final t1 = DateTime.now().millisecondsSinceEpoch;
      print('[MenuScreen] LATENCY: voice->action: ${t1 - t0}ms');
      _pushAndRefreshMenu(WearHelpScreen.route);
    } else if (_focusedIndex == 3) {
      print('[MenuScreen] NAVIGATING TO: WearSettingsScreen');
      final t1 = DateTime.now().millisecondsSinceEpoch;
      print('[MenuScreen] LATENCY: voice->action: ${t1 - t0}ms');
      _pushAndRefreshMenu(WearSettingsScreen.route);
    } else {
      print('[MenuScreen] _focusedIndex=$_focusedIndex is out of bounds!');
    }
    print('[MenuScreen] ========== _onVoiceSelect END ==========');
  }

  int _focusedListIndex() {
    // Используем _focusedIndex напрямую вместо вычисления из scroll
    // _focusedIndex: 0=Печать ценника, 1=Доступность, 2=Справка, 3=Настройки
    print(
      '[MenuScreen] _focusedListIndex: returning _focusedIndex=$_focusedIndex',
    );
    return _focusedIndex;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      Align(
        alignment: Alignment.topCenter,
        child: Text(
          'Меню',
          style: WearTypography.lable15,
          textAlign: TextAlign.center,
        ),
      ),
      WearPill(
        title: 'Печать ценника',
        onTap: () {
          _pushAndRefreshMenu(WearPrinterSelectScreen.route);
        },
      ),
      WearPill(
        title: 'Доступность',
        onTap: () => _pushAndRefreshMenu(WearAvailabilityInteractionScreen.route),
      ),
      WearPill(
        title: 'Справка',
        onTap: () => _pushAndRefreshMenu(WearHelpScreen.route),
      ),
      WearPill(
        title: 'Настройки',
        icon: WearImages.gear,
        onTap: () => _pushAndRefreshMenu(WearSettingsScreen.route),
      ),
      const SizedBox(
        height: 50,
      )
    ];

    return WearVoiceCommandListener(
      onUp: _onVoiceUp,
      onDown: _onVoiceDown,
      onSelect: _onVoiceSelect,
      child: WearScreenScaffold(
        scrollController: _scroll,
        child: WearScalingListView(
          controller: _scroll,
          itemCount: items.length,
          itemExtent: 56,
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 4.5),
          edgeFractionTop: 0.06,
          edgeFractionBottom: 0.14,
          minScale: 0.72,
          minOpacity: 0.30,
          baseSideInset: 10,
          extraSideInset: 30,
          itemBuilder: (BuildContext context, int i) => items[i],
          onFocusChanged: (int listIndex) {
            print('[MenuScreen] onFocusChanged: listIndex=$listIndex');
            print(
              '[MenuScreen] WIDGETS: [0]=Меню, [1]=Печать, [2]=Доступность, [3]=Справка, [4]=Настройки, [5]=Spacer',
            );
            final int itemIndex = (listIndex - 1).clamp(0, _menuItemCount - 1);
            print(
              '[MenuScreen] onFocusChanged: itemIndex=$itemIndex => ${_getMenuItemName(itemIndex)}',
            );
            _focusedIndex = itemIndex;
            print(
              '[MenuScreen] onFocusChanged: _focusedIndex updated to: $_focusedIndex',
            );
            WearStatusIconReporter.I.sendFast(
              WearGlassesPayload.menu(selectedIndex: itemIndex),
            );
          },
        ),
      ),
    );
  }
}
