/// Application constants
class AppConstants {
  AppConstants._();

  /// Method channel names
  static const String appChannelName = 'app_channel';
  static const String glassesChannelName = 'glasses_channel';

  /// Voice recognition debounce delays
  static const int voiceUiUpdateDelayMs = 300;
  static const int voiceSendDelayMs = 500;
  static const int voicePartialResultPollingMs = 350;
}
