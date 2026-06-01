library analytics;

class AnalyticsEvent {
  final String name;
  final Map<String, dynamic>? parameters;

  const AnalyticsEvent(this.name, {this.parameters});
}

class Analytics {
  static Future<void> sendEvent(AnalyticsEvent event) async {
    // stub — no-op
  }
}
