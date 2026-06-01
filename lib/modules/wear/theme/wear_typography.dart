import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:pole_base_kit/pole_base_kit.dart';

abstract class WearTypography {
  static final TextStyle size20 = PBTextStyles.captionLargeAccent.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 0,
    color: WearColors.textDefault,
  );

  static final TextStyle lable18 = PBTextStyles.captionLargeAccent.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: WearColors.textDefault,
  );

  static final TextStyle lable15 = PBTextStyles.captionLargeAccent.copyWith(
    fontWeight: FontWeight.w500,
    fontSize: 15,
    color: WearColors.textDefault,
  );

  static final TextStyle lable = PBTextStyles.captionLargeAccent.copyWith(
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: WearColors.textDefault,
  );

  static final TextStyle bodyxsm = PBTextStyles.captionLargeAccent.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 10,
    color: WearColors.textSecondary,
  );

  static final TextStyle bodysml = PBTextStyles.captionLargeAccent.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: WearColors.textDefault,
  );
}
