import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';

abstract class WearTypography {
  static const TextStyle _base = TextStyle();

  static final TextStyle size20 = _base.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 0,
    color: WearColors.textDefault,
  );

  static final TextStyle lable18 = _base.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: WearColors.textDefault,
  );

  static final TextStyle lable15 = _base.copyWith(
    fontWeight: FontWeight.w500,
    fontSize: 15,
    color: WearColors.textDefault,
  );

  static final TextStyle lable = _base.copyWith(
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: WearColors.textDefault,
  );

  static final TextStyle bodyxsm = _base.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 10,
    color: WearColors.textSecondary,
  );

  static final TextStyle bodysml = _base.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: WearColors.textDefault,
  );
}
