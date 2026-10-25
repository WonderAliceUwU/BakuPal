part of '../../main.dart';

/// How the Bakugan are drawn in their small previews: the 3D model or the cartoon
/// ball sprite kept in the `Cartoon` folder of each model.
enum BakuganPreviewStyle { model3d, cartoon }

extension BakuganPreviewStyleX on BakuganPreviewStyle {
  String get code => name;

  String label(AppLanguage language) {
    final es = language == AppLanguage.es;
    switch (this) {
      case BakuganPreviewStyle.model3d:
        return es ? 'MODELO 3D' : '3D MODEL';
      case BakuganPreviewStyle.cartoon:
        return es ? 'DIBUJO' : 'CARTOON';
    }
  }

  String description(AppLanguage language) {
    final es = language == AppLanguage.es;
    switch (this) {
      case BakuganPreviewStyle.model3d:
        return es
            ? 'Las previews pequeñas muestran el modelo 3D de cada Bakugan.'
            : 'Small previews show the 3D model of each Bakugan.';
      case BakuganPreviewStyle.cartoon:
        return es
            ? 'Las previews pequeñas muestran la bola dibujada del anime; las grandes siguen en 3D. Si un Bakugan no tiene dibujo, se usa su modelo 3D.'
            : 'Small previews show the drawn ball from the anime; large ones stay in 3D. A Bakugan with no drawing uses its 3D model.';
    }
  }
}

class PreviewStyleController extends ChangeNotifier {
  static final PreviewStyleController instance = PreviewStyleController._();
  PreviewStyleController._();

  BakuganPreviewStyle _style = BakuganPreviewStyle.model3d;
  bool _initialized = false;

  BakuganPreviewStyle get style => _style;

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
    for (final style in BakuganPreviewStyle.values) {
      if (style.code == settings['previewStyle']) _style = style;
    }
  }

  Future<void> setStyle(BakuganPreviewStyle style) async {
    if (_style == style) return;
    _style = style;
    notifyListeners();
    await _saveAppSettings({'previewStyle': style.code});
  }
}

// Each species keeps its sprites next to its 3D model, in
// `<model folder>/Cartoon/<attribute>.png`. Keyed by '<species slug>/<attribute>'.
final Map<String, String> _cartoonSpritePaths = {};

void _indexCartoonSprites(List<String> assetPaths) {
  _cartoonSpritePaths.clear();
  for (final path in assetPaths) {
    if (!path.startsWith(_seasonOneModelsRoot) &&
        !path.startsWith(_seasonTwoModelsRoot)) {
      continue;
    }
    final match = RegExp(r'/Cartoon/([a-z]+)\.png$').firstMatch(path);
    if (match == null) continue;
    final species = _speciesNameFromRoot(_modelSpeciesRoot(path));
    _cartoonSpritePaths['${_assetSlug(species)}/${match.group(1)}'] = path;
  }
}

/// The cartoon sprite of [variant], or null when there is none for its
/// species and attribute.
String? cartoonSpritePathFor(BakuganVariant variant) {
  return _cartoonSpritePaths['${_assetSlug(variant.speciesName)}/'
      '${variant.attribute.toLowerCase()}'];
}
