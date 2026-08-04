class WearListScrollMetrics {
  const WearListScrollMetrics({
    required this.pageIndex,
    required this.pageCount,
    required this.thumbExtent,
    required this.thumbOffset,
    required this.progress,
  });

  final int pageIndex;
  final int pageCount;
  final double thumbExtent;
  final double thumbOffset;
  final double progress;

  factory WearListScrollMetrics.fromPageText(
    String pageText, {
    required double trackExtent,
    int selectedIndex = 0,
    int visibleItemCount = 1,
    double minThumbExtent = 24,
    double maxThumbExtent = 71,
  }) {
    final RegExpMatch? match =
        RegExp(r'(\d+)\s+из\s+(\d+)', caseSensitive: false)
            .firstMatch(pageText);
    final int rawPage = int.tryParse(match?.group(1) ?? '') ?? 1;
    final int rawCount = int.tryParse(match?.group(2) ?? '') ?? 1;
    return WearListScrollMetrics.calculate(
      pageIndex: rawPage - 1,
      pageCount: rawCount,
      trackExtent: trackExtent,
      selectedIndex: selectedIndex,
      visibleItemCount: visibleItemCount,
      minThumbExtent: minThumbExtent,
      maxThumbExtent: maxThumbExtent,
    );
  }

  factory WearListScrollMetrics.calculate({
    required int pageIndex,
    required int pageCount,
    required double trackExtent,
    int selectedIndex = 0,
    int visibleItemCount = 1,
    double minThumbExtent = 24,
    double maxThumbExtent = 71,
  }) {
    final int safeCount = pageCount < 1 ? 1 : pageCount;
    final int safeIndex = pageIndex.clamp(0, safeCount - 1);
    final double safeTrack = trackExtent < 0 ? 0 : trackExtent;
    final double upperThumb =
        maxThumbExtent.clamp(0.0, safeTrack).toDouble();
    final double lowerThumb =
        minThumbExtent.clamp(0.0, upperThumb).toDouble();
    final double thumbExtent = safeCount <= 1
        ? safeTrack
        : (safeTrack / safeCount)
            .clamp(lowerThumb, upperThumb)
            .toDouble();
    final int safeVisibleCount = visibleItemCount < 1 ? 1 : visibleItemCount;
    final int safeSelectedIndex =
        selectedIndex.clamp(0, safeVisibleCount - 1);
    final double withinPageProgress = safeVisibleCount <= 1
        ? (safeIndex == safeCount - 1 ? 1.0 : 0.0)
        : safeSelectedIndex / (safeVisibleCount - 1);
    final double progress = safeCount <= 1
        ? 0.0
        : ((safeIndex + withinPageProgress) / safeCount)
            .clamp(0.0, 1.0)
            .toDouble();
    final double travel = safeTrack - thumbExtent;
    final double thumbOffset = travel * progress;
    return WearListScrollMetrics(
      pageIndex: safeIndex,
      pageCount: safeCount,
      thumbExtent: thumbExtent,
      thumbOffset: thumbOffset,
      progress: progress,
    );
  }
}
