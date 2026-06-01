import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WearModeToggle extends StatelessWidget {
  const WearModeToggle({
    super.key,
    required this.isDigits,
    required this.onDigits,
    required this.onVoice,
  });

  final bool isDigits;
  final VoidCallback onDigits;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return _WearBlobSwitch(
      isLeftActive: isDigits,
      onLeftTap: onDigits,
      onRightTap: onVoice,
    );
  }
}

class _WearBlobSwitch extends StatelessWidget {
  const _WearBlobSwitch({
    required this.isLeftActive,
    required this.onLeftTap,
    required this.onRightTap,
  });

  final bool isLeftActive;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;

  static const double _w = 88;
  static const double _h = 34;
  static const double _indicatorW = 49;

  static const Duration _dur = Duration(milliseconds: 260);
  static const Curve _curve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    final double target = isLeftActive ? 0.0 : 1.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: _dur,
      curve: _curve,
      builder: (BuildContext context, double t, _) {
        final double dx = (_w - _indicatorW) * t;

        final Color digitsColor = Color.lerp(
          WearColors.white,
          WearColors.textDefault,
          t,
        )!;
        final Color micColor = Color.lerp(
          WearColors.textDefault,
          WearColors.white,
          t,
        )!;

        final double flip = (((t - 0.5) / 0.16) + 0.5).clamp(0.0, 1.0);

        final double s = math.sin(math.pi * t);
        final double sx = 1.0 + 0.06 * s;
        final double sy = 1.0 - 0.03 * s;

        return SizedBox(
          width: _w,
          height: _h,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const _TintedAsset(
                WearImages.modeToggleBack,
                color: WearColors.buttonSecondaryDefault,
                width: _w,
                height: _h,
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Transform.translate(
                  offset: Offset(dx, 0),
                  child: Transform.scale(
                    scaleX: sx,
                    scaleY: sy,
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: _indicatorW,
                        height: _h,
                        child: Stack(
                          children: <Widget>[
                            Opacity(
                              opacity: 1.0 - flip,
                              child: const _TintedAsset(
                                WearImages.modeToggleIndicator,
                                color: WearColors.buttonPrimary,
                                width: _indicatorW,
                                height: _h,
                              ),
                            ),
                            Opacity(
                              opacity: flip,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..scale(-1.0, 1.0),
                                child: const _TintedAsset(
                                  WearImages.modeToggleIndicator,
                                  color: WearColors.buttonPrimary,
                                  width: _indicatorW,
                                  height: _h,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onLeftTap,
                          child: SvgPicture.asset(
                            WearImages.curvedText,
                            colorFilter:
                                ColorFilter.mode(digitsColor, BlendMode.srcIn),
                          )),
                    ),
                    Expanded(
                      child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onRightTap,
                          child: SvgPicture.asset(
                            WearImages.microphone,
                            colorFilter:
                                ColorFilter.mode(micColor, BlendMode.srcIn),
                          )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TintedAsset extends StatelessWidget {
  const _TintedAsset(
    this.asset, {
    required this.color,
    required this.width,
    required this.height,
  });

  final String asset;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final String lower = asset.toLowerCase();
    final bool isSvg = lower.endsWith('.svg');

    if (isSvg) {
      return FutureBuilder<String>(
        future: DefaultAssetBundle.of(context).loadString(asset),
        builder: (BuildContext context, AsyncSnapshot<String> snap) {
          if (snap.hasError) {
            return _MissingAssetBox(asset, width: width, height: height);
          }
          if (!snap.hasData) {
            return SizedBox(width: width, height: height);
          }

          return ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: SvgPicture.string(
              snap.data!,
              width: width,
              height: height,
              fit: BoxFit.fill,
              allowDrawingOutsideViewBox: true,
              clipBehavior: Clip.none,
            ),
          );
        },
      );
    }

    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        asset,
        width: width,
        height: height,
        fit: BoxFit.fill,
        errorBuilder: (_, __, ___) =>
            _MissingAssetBox(asset, width: width, height: height),
      ),
    );
  }
}

class _MissingAssetBox extends StatelessWidget {
  const _MissingAssetBox(this.asset,
      {required this.width, required this.height});

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.red),
        color: Colors.red.withValues(alpha: 0.08),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: Text(
        'ASSET NOT FOUND\n$asset',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 8),
      ),
    );
  }
}
