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
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          final saved = data['style']?.toString();
          for (final style in BakuganPreviewStyle.values) {
            if (style.code == saved) _style = style;
          }
        }
      }
    } catch (_) {}
    _initialized = true;
    notifyListeners();
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/bakugan_preview_style_settings.json');
  }

  Future<void> setStyle(BakuganPreviewStyle style) async {
    if (_style == style) return;
    _style = style;
    notifyListeners();
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode({'style': style.code}));
    } catch (_) {}
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
