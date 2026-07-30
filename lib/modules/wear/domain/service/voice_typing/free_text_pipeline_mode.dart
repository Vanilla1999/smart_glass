enum FreeTextPipelineMode {
  replayOnly,
  shadowLive,
  liveWithReplayFallback;

  static FreeTextPipelineMode parse(String? value) {
    return switch (value?.trim()) {
      'shadowLive' => FreeTextPipelineMode.shadowLive,
      'liveWithReplayFallback' => FreeTextPipelineMode.liveWithReplayFallback,
      _ => FreeTextPipelineMode.replayOnly,
    };
  }

  bool get usesLiveLane => this != FreeTextPipelineMode.replayOnly;
}
