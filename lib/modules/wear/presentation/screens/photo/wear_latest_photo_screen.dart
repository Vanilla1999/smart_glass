import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearLatestPhotoScreen extends StatefulWidget {
  const WearLatestPhotoScreen({super.key});

  static const String route = '/wear_latest_photo';

  @override
  State<WearLatestPhotoScreen> createState() => _WearLatestPhotoScreenState();
}

class _WearLatestPhotoScreenState extends State<WearLatestPhotoScreen> {
  late final Future<File?> _photo;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(WearScreenId.latestPhoto);
    _photo = WearDependencies.I.photoStore.latestPhoto();
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      showHomeButton: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 52, 18, 18),
        child: FutureBuilder<File?>(
          future: _photo,
          builder: (BuildContext context, AsyncSnapshot<File?> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: WearLoading(size: 44));
            }
            final File? photo = snapshot.data;
            if (snapshot.hasError || photo == null) {
              return Center(
                child: Text(
                  snapshot.hasError
                      ? 'Не удалось открыть фотографию'
                      : 'Фотография еще не сделана',
                  style: WearTypography.lable,
                  textAlign: TextAlign.center,
                ),
              );
            }
            return Column(
              children: <Widget>[
                Text('Последнее фото', style: WearTypography.lable18),
                const SizedBox(height: 12),
                Expanded(
                  child: InteractiveViewer(
                    child: Image.file(
                      photo,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          'Не удалось открыть фотографию',
                          style: WearTypography.lable,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
