import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bakugan_companion/main.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String supportPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bakupal_settings_');
    // Not created yet, like on a fresh install.
    supportPath = '${root.path}/support';
    PathProviderPlatform.instance = _FakePathProviderPlatform(supportPath);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async => null,
      );
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, dynamic> savegameSettings() {
    final store = jsonDecode(
      File('$supportPath/bakugan_leaderboard.json').readAsStringSync(),
    );
    return Map<String, dynamic>.from(store['settings'] as Map);
  }

  test('the old settings files move into the savegame', () async {
    Directory(supportPath).createSync(recursive: true);
    File(
      '$supportPath/bakugan_volume_settings.json',
    ).writeAsStringSync(jsonEncode({'volume': 0.4, 'muted': true}));
    File(
      '$supportPath/bakugan_automation_settings.json',
    ).writeAsStringSync(jsonEncode({'level': 'auto'}));

    await AppVolumeController.instance.init();

    expect(AppVolumeController.instance.volume, 0.4);
    expect(AppVolumeController.instance.isMuted, isTrue);
    expect(savegameSettings(), {
      'volume': 0.4,
      'muted': true,
      'automationLevel': 'auto',
    });
    expect(
      File('$supportPath/bakugan_volume_settings.json').existsSync(),
      isFalse,
    );
  });

  test('settings are saved in the savegame', () async {
    await AutomationController.instance.setLevel(AutomationLevel.manual);
    await PreviewStyleController.instance.setStyle(BakuganPreviewStyle.cartoon);
    await LanguageController.instance.setLanguages(
      ui: AppLanguage.es,
      card: AppLanguage.en,
    );
    await AppVolumeController.instance.setVolume(0.3);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(savegameSettings(), {
      'automationLevel': 'manual',
      'previewStyle': 'cartoon',
      'uiLanguage': 'es',
      'cardLanguage': 'en',
      'volume': 0.3,
      'muted': false,
    });
  });

  test('importing a savegame applies its settings', () async {
    final backup = File('${root.path}/backup.json');
    final exported = jsonDecode(
      File(
        await LeaderboardRepository.instance.exportToFile(backup.path),
      ).readAsStringSync(),
    );
    exported['settings'] = {
      'automationLevel': 'assisted',
      'previewStyle': 'model3d',
      'uiLanguage': 'en',
      'cardLanguage': 'es',
      'volume': 0.8,
      'muted': false,
    };
    backup.writeAsStringSync(jsonEncode(exported));

    await LeaderboardRepository.instance.importFromFile(backup.path);
    await applyImportedAppSettings();

    expect(AutomationController.instance.level, AutomationLevel.assisted);
    expect(PreviewStyleController.instance.style, BakuganPreviewStyle.model3d);
    expect(LanguageController.instance.uiLanguage, AppLanguage.en);
    expect(LanguageController.instance.cardLanguage, AppLanguage.es);
    expect(AppVolumeController.instance.volume, 0.8);
  });
}
