import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

/// Test to verify voice command routing logic
/// 
/// This test verifies that voice commands are correctly routed to the 
/// active screen only, and that focusedIndex state management works correctly.
///
/// Expected flow:
/// 1. Menu Screen (index 0 = "Печать ценника", index 1 = "Справка", index 2 = "Настройки")
/// 2. Voice "вниз" -> index becomes 1
/// 3. Voice "вниз" -> index becomes 2  
/// 4. Voice "вверх" -> index becomes 1
/// 5. Voice "вниз" -> index becomes 2
/// 6. Voice "выбрать" -> navigate to screen for index 2 (Настройки)
///
/// Problem observed:
/// - When navigating to PrinterSelect via push(), BOTH MenuScreen and PrinterSelect
///   receive voice commands because WearVoiceCommandListener exists on both screens
/// - This causes MenuScreen to update _focusedIndex even though it's not visible
void main() {
  group('Voice Navigation Logic Tests', () {
    test('VoiceDown increments focusedIndex correctly', () {
      int focusedIndex = 0;
      const int menuItemCount = 3;

      // Simulate voice down
      void onVoiceDown() {
        if (focusedIndex < menuItemCount - 1) {
          focusedIndex++;
        }
      }

      onVoiceDown();
      expect(focusedIndex, 1);

      onVoiceDown();
      expect(focusedIndex, 2);

      // Should not go beyond last item
      onVoiceDown();
      expect(focusedIndex, 2); // Still 2, at bottom
    });

    test('VoiceUp decrements focusedIndex correctly', () {
      int focusedIndex = 2;

      // Simulate voice up
      void onVoiceUp() {
        if (focusedIndex > 0) {
          focusedIndex--;
        }
      }

      onVoiceUp();
      expect(focusedIndex, 1);

      onVoiceUp();
      expect(focusedIndex, 0);

      // Should not go negative
      onVoiceUp();
      expect(focusedIndex, 0); // Still 0, at top
    });

    test('Navigation maps focusedIndex to correct screen', () {
      int focusedIndex = 0;
      String? navigatedTo;

      void onSelect() {
        switch (focusedIndex) {
          case 0:
            navigatedTo = 'WearPrinterSelectScreen';
            break;
          case 1:
            navigatedTo = 'WearHelpScreen';
            break;
          case 2:
            navigatedTo = 'WearSettingsScreen';
            break;
        }
      }

      // Test navigation for each menu item
      focusedIndex = 0;
      onSelect();
      expect(navigatedTo, 'WearPrinterSelectScreen');

      focusedIndex = 1;
      onSelect();
      expect(navigatedTo, 'WearHelpScreen');

      focusedIndex = 2;
      onSelect();
      expect(navigatedTo, 'WearSettingsScreen');
    });

    test('BUG: Both screens receive voice commands - problem demonstration', () async {
      // This test demonstrates the bug where both screens receive commands
      
      final commandsController = StreamController<WearVoiceCommand>.broadcast();
      
      int menuFocusedIndex = 0;
      int printerFocusedIndex = 0;
      
      bool menuReceivedCommand = false;
      bool printerReceivedCommand = false;

      // MenuScreen listener
      final menuSubscription = commandsController.stream.listen((cmd) {
        menuReceivedCommand = true;
        if (cmd == WearVoiceCommand.down) {
          menuFocusedIndex++;
        }
      });

      // PrinterSelect listener (overlaid screen)  
      final printerSubscription = commandsController.stream.listen((cmd) {
        printerReceivedCommand = true;
        if (cmd == WearVoiceCommand.down) {
          printerFocusedIndex++;
        }
      });

      // Emit a command
      commandsController.add(WearVoiceCommand.down);
      
      await Future.delayed(Duration.zero);
      
      // BUG: Both listeners received the command!
      expect(menuReceivedCommand, true, reason: 'MenuScreen should receive command');
      expect(printerReceivedCommand, true, reason: 'PrinterSelect ALSO receives command (BUG!)');
      
      // This causes MenuScreen to update its focusedIndex even though it's not visible
      expect(menuFocusedIndex, 1, reason: 'MenuScreen updated even though PrinterSelect is shown');
      expect(printerFocusedIndex, 1);
      
      await menuSubscription.cancel();
      await printerSubscription.cancel();
      await commandsController.close();
    });

    test('SOLUTION: Only active screen should receive commands', () async {
      // This test demonstrates the correct behavior
      
      final commandsController = StreamController<WearVoiceCommand>.broadcast();
      
      int currentScreenIndex = 0; // 0 = MenuScreen, 1 = PrinterSelect
      int menuFocusedIndex = 0;
      int printerFocusedIndex = 0;
      
      // Global listener that routes to active screen only
      final globalSubscription = commandsController.stream.listen((cmd) {
        switch (currentScreenIndex) {
          case 0: // MenuScreen active
            if (cmd == WearVoiceCommand.down && menuFocusedIndex < 2) {
              menuFocusedIndex++;
            } else if (cmd == WearVoiceCommand.up && menuFocusedIndex > 0) {
              menuFocusedIndex--;
            }
            break;
          case 1: // PrinterSelect active
            if (cmd == WearVoiceCommand.down && printerFocusedIndex < 2) {
              printerFocusedIndex++;
            } else if (cmd == WearVoiceCommand.up && printerFocusedIndex > 0) {
              printerFocusedIndex--;
            }
            break;
        }
      });

      // Emit a command when MenuScreen is active
      currentScreenIndex = 0;
      commandsController.add(WearVoiceCommand.down);
      await Future.delayed(Duration.zero);
      
      expect(menuFocusedIndex, 1, reason: 'MenuScreen should receive command');
      expect(printerFocusedIndex, 0, reason: 'PrinterSelect should NOT receive command');

      // Navigate to PrinterSelect
      currentScreenIndex = 1;
      commandsController.add(WearVoiceCommand.down);
      await Future.delayed(Duration.zero);
      
      expect(menuFocusedIndex, 1, reason: 'MenuScreen should not change');
      expect(printerFocusedIndex, 1, reason: 'PrinterSelect should receive command');

      await globalSubscription.cancel();
      await commandsController.close();
    });
  });

  group('Menu Screen Voice Navigation Flow', () {
    test('Complete flow: menu navigation to printer select', () {
      // Simulate the full user flow:
      // 1. Start at menu (focusedIndex = 0 = "Печать ценника")
      // 2. Voice "вниз" -> focus 1 = "Справка"
      // 3. Voice "вниз" -> focus 2 = "Настройки"
      // 4. Voice "вверх" -> focus 1 = "Справка"
      // 5. Voice "вниз" -> focus 2 = "Настройки"
      // 6. Voice "выбрать" -> navigate to "Настройки"

      int focusedIndex = 0;
      String? navigatedTo;

      void voiceDown() {
        if (focusedIndex < 2) focusedIndex++;
      }

      void voiceUp() {
        if (focusedIndex > 0) focusedIndex--;
      }

      void voiceSelect() {
        switch (focusedIndex) {
          case 0:
            navigatedTo = 'WearPrinterSelectScreen';
            break;
          case 1:
            navigatedTo = 'WearHelpScreen';
            break;
          case 2:
            navigatedTo = 'WearSettingsScreen';
            break;
        }
      }

      // Step 1: Start at "Печать ценника"
      expect(focusedIndex, 0);

      // Step 2: вниз -> "Справка"
      voiceDown();
      expect(focusedIndex, 1);

      // Step 3: вниз -> "Настройки"
      voiceDown();
      expect(focusedIndex, 2);

      // Step 4: верх -> "Справка"
      voiceUp();
      expect(focusedIndex, 1);

      // Step 5: вниз -> "Настройки"
      voiceDown();
      expect(focusedIndex, 2);

      // Step 6: выбрать -> "Настройки"
      voiceSelect();
      expect(navigatedTo, 'WearSettingsScreen');
    });

    test('Complete flow: menu navigation directly to printer select', () {
      // User says "выбрать" immediately without moving focus
      int focusedIndex = 0;
      String? navigatedTo;

      void voiceSelect() {
        switch (focusedIndex) {
          case 0:
            navigatedTo = 'WearPrinterSelectScreen';
            break;
          case 1:
            navigatedTo = 'WearHelpScreen';
            break;
          case 2:
            navigatedTo = 'WearSettingsScreen';
            break;
        }
      }

      // Should navigate to "Печать ценника" (index 0)
      voiceSelect();
      expect(navigatedTo, 'WearPrinterSelectScreen');
    });
  });
}
