part of '../../main.dart';

/// How much the app resolves by itself during a match.
///
/// - manual: the game master applies every effect; the manual tools are shown.
/// - assisted: the app computes what it can, the game master confirms the rest
///   and the manual tools stay in reach.
/// - auto: the app applies the effects it knows and hides the manual tools
///   (switch to assisted, even mid-match, to get them back).
enum AutomationLevel { manual, assisted, auto }

extension AutomationLevelX on AutomationLevel {
  String get code => name;

  String label(AppLanguage language) {
    final es = language == AppLanguage.es;
    switch (this) {
      case AutomationLevel.manual:
        return es ? 'MANUAL' : 'MANUAL';
      case AutomationLevel.assisted:
        return es ? 'ASISTIDO' : 'ASSISTED';
      case AutomationLevel.auto:
        return es ? 'AUTOMÁTICO' : 'AUTO';
    }
  }

  String description(AppLanguage language) {
    final es = language == AppLanguage.es;
    switch (this) {
      case AutomationLevel.manual:
        return es
            ? 'La app no suma bonus ni aplica efectos. Los botones manuales están siempre visibles.'
            : 'The app adds no bonuses and applies no effects. The manual buttons are always visible.';
      case AutomationLevel.assisted:
        return es
            ? 'La app suma los bonus y aplica los efectos que conoce, con un respaldo manual siempre a la vista.'
            : 'The app adds the bonuses and applies the effects it knows, with a manual fallback always in view.';
      case AutomationLevel.auto:
        return es
            ? 'La app se encarga de los bonus y de los efectos que conoce, sin botones manuales de por medio.'
            : 'The app takes care of the bonuses and the effects it knows, with no manual buttons in the way.';
    }
  }

  /// Whether the manual tools (G-Power "+", change result, global effect "+")
  /// are available.
  bool get showsManualTools => this != AutomationLevel.auto;
}

class AutomationController extends ChangeNotifier {
  static final AutomationController instance = AutomationController._();
  AutomationController._();

  AutomationLevel _level = AutomationLevel.assisted;
  bool _initialized = false;

  AutomationLevel get level => _level;

  Future<void> init() async {
    if (_initialized) return;
    _readSettings(await _loadAppSettings());
    _initialized = true;
    notifyListeners();
  }

  void applySettings(Map<String, dynamic> settings) {
    _readSettings(settings);
    notifyListeners();
  }

  void _readSettings(Map<String, dynamic> settings) {
    for (final level in AutomationLevel.values) {
      if (level.code == settings['automationLevel']) _level = level;
    }
  }

  Future<void> setLevel(AutomationLevel level) async {
    if (_level == level) return;
    _level = level;
    notifyListeners();
    await _saveAppSettings({'automationLevel': level.code});
  }
}
