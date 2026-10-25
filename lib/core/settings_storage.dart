part of '../main.dart';

// The app settings live in the savegame (`settings` in the leaderboard store),
// so exporting and importing it carries them too. Keys:
//   uiLanguage, cardLanguage: 'en' | 'es'
//   automationLevel: AutomationLevel.code
//   previewStyle: BakuganPreviewStyle.code
//   volume: 0..1, muted: bool

// Before, each setting had a JSON file of its own in the app support folder:
// their values are moved into the savegame once, then the files are removed.
const _legacySettingsFiles = {
  'bakugan_language_settings.json': {
    'uiLanguage': 'uiLanguage',
    'cardLanguage': 'cardLanguage',
  },
  'bakugan_automation_settings.json': {'level': 'automationLevel'},
  'bakugan_preview_style_settings.json': {'style': 'previewStyle'},
  'bakugan_volume_settings.json': {'volume': 'volume', 'muted': 'muted'},
};

Future<Map<String, dynamic>>? _appSettingsLoad;

/// The saved app settings, read once per launch.
Future<Map<String, dynamic>> _loadAppSettings() {
  return _appSettingsLoad ??= () async {
    try {
      final store = await LeaderboardRepository.instance.loadStore();
      final legacy = await _takeLegacySettings();
      if (legacy.isEmpty) return store.settings;
      // Values already in the savegame win over the old files.
      final merged = {...legacy, ...store.settings};
      await LeaderboardRepository.instance.saveSettings(merged);
      return merged;
    } catch (error) {
      debugPrint('Could not read the app settings: $error');
      return const <String, dynamic>{};
    }
  }();
}

Future<Map<String, dynamic>> _takeLegacySettings() async {
  final settings = <String, dynamic>{};
  final dir = await getApplicationSupportDirectory();
  for (final entry in _legacySettingsFiles.entries) {
    final file = File('${dir.path}/${entry.key}');
    if (!await file.exists()) continue;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        for (final key in entry.value.entries) {
          if (data[key.key] != null) settings[key.value] = data[key.key];
        }
      }
      await file.delete();
    } catch (error) {
      debugPrint('Could not move the settings in ${entry.key}: $error');
    }
  }
  return settings;
}

Future<void> _saveAppSettings(Map<String, dynamic> changes) async {
  try {
    await LeaderboardRepository.instance.saveSettings(changes);
  } catch (error) {
    debugPrint('Could not save the app settings: $error');
  }
}

/// Applies the settings of a savegame that was just imported.
Future<void> applyImportedAppSettings() async {
  final store = await LeaderboardRepository.instance.loadStore();
  _appSettingsLoad = Future.value(store.settings);
  LanguageController.instance.applySettings(store.settings);
  AutomationController.instance.applySettings(store.settings);
  PreviewStyleController.instance.applySettings(store.settings);
  await AppVolumeController.instance.applySettings(store.settings);
}
