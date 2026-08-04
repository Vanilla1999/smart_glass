import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_list_scroll_metrics.dart';

void main() {
  group('WearListScrollMetrics', () {
    test('first item on first page places thumb at the top', () {
      final WearListScrollMetrics metrics =
          WearListScrollMetrics.fromPageText(
        'Страница: 1 из 5',
        trackExtent: 156,
        selectedIndex: 0,
        visibleItemCount: 4,
      );

      expect(metrics.pageIndex, 0);
      expect(metrics.pageCount, 5);
      expect(metrics.progress, 0);
      expect(metrics.thumbOffset, 0);
      expect(metrics.thumbExtent, greaterThan(0));
    });

    test('thumb moves between rows inside one visible page', () {
      final WearListScrollMetrics first =
          WearListScrollMetrics.fromPageText(
        'Страница: 1 из 5',
        trackExtent: 156,
        selectedIndex: 0,
        visibleItemCount: 4,
      );
      final WearListScrollMetrics fourth =
          WearListScrollMetrics.fromPageText(
        'Страница: 1 из 5',
        trackExtent: 156,
        selectedIndex: 3,
        visibleItemCount: 4,
      );

      expect(fourth.progress, moreOrLessEquals(0.2));
      expect(fourth.thumbOffset, greaterThan(first.thumbOffset));
    });

    test('page boundary does not make the thumb jump backwards', () {
      final WearListScrollMetrics endOfFirst =
          WearListScrollMetrics.fromPageText(
        'Страница: 1 из 5',
        trackExtent: 156,
        selectedIndex: 3,
        visibleItemCount: 4,
      );
      final WearListScrollMetrics startOfSecond =
          WearListScrollMetrics.fromPageText(
        'Страница: 2 из 5',
        trackExtent: 156,
        selectedIndex: 0,
        visibleItemCount: 4,
      );

      expect(
        startOfSecond.thumbOffset,
        moreOrLessEquals(endOfFirst.thumbOffset),
      );
    });

    test('last visible item on last page places thumb at the bottom', () {
      final WearListScrollMetrics metrics =
          WearListScrollMetrics.fromPageText(
        'Страница: 5 из 5',
        trackExtent: 156,
        selectedIndex: 1,
        visibleItemCount: 2,
      );

      expect(metrics.progress, 1);
      expect(
        metrics.thumbOffset,
        moreOrLessEquals(156 - metrics.thumbExtent),
      );
    });

    test('many pages keep a visible minimum thumb', () {
      final WearListScrollMetrics metrics =
          WearListScrollMetrics.fromPageText(
        'Страница: 12 из 23',
        trackExtent: 156,
        selectedIndex: 2,
        visibleItemCount: 4,
      );

      expect(metrics.thumbExtent, 24);
      expect(metrics.thumbOffset, greaterThan(0));
    });

    test('malformed page text safely falls back to one page', () {
      final WearListScrollMetrics metrics =
          WearListScrollMetrics.fromPageText(
        'нет страницы',
        trackExtent: 156,
        selectedIndex: 3,
        visibleItemCount: 4,
      );

      expect(metrics.pageIndex, 0);
      expect(metrics.pageCount, 1);
      expect(metrics.progress, 0);
      expect(metrics.thumbOffset, 0);
      expect(metrics.thumbExtent, 156);
    });
  });
}
