import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bakugan_companion/main.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('automation level', () {
    test('only auto hides the manual tools', () {
      expect(AutomationLevel.manual.showsManualTools, isTrue);
      expect(AutomationLevel.assisted.showsManualTools, isTrue);
      expect(AutomationLevel.auto.showsManualTools, isFalse);
    });

    test('every level has a description in both languages', () {
      for (final level in AutomationLevel.values) {
        for (final language in AppLanguage.values) {
          expect(level.label(language), isNotEmpty);
          expect(level.description(language), isNotEmpty);
        }
      }
    });

    test('is saved and read back from disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('automation_test_');
      final originalPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() async {
        PathProviderPlatform.instance = originalPlatform;
        await tempDir.delete(recursive: true);
      });

      final controller = AutomationController.instance;
      await controller.setLevel(AutomationLevel.manual);
      expect(controller.level, AutomationLevel.manual);

      final saved = File('${tempDir.path}/bakugan_automation_settings.json');
      expect(await saved.exists(), isTrue);
      expect(await saved.readAsString(), contains('manual'));

      await controller.setLevel(AutomationLevel.assisted);
      expect(await saved.readAsString(), contains('assisted'));
    });
  });

  group('close-loss effect (Subterra)', () {
    const condition = {'your_attribute': 'subterra', 'loss_margin_lt': 100};

    test('applies for the loser with a Subterra Bakugan, by less than 100', () {
      expect(
        closeLossEffectBlockedReason(
          condition: condition,
          playerIsLoser: true,
          loserAttribute: 'subterra',
          margin: 90,
        ),
        isNull,
      );
    });

    test('does not apply from the winner', () {
      expect(
        closeLossEffectBlockedReason(
          condition: condition,
          playerIsLoser: false,
          loserAttribute: 'subterra',
          margin: 10,
        ),
        isNotNull,
      );
    });

    test('does not apply with another attribute', () {
      expect(
        closeLossEffectBlockedReason(
          condition: condition,
          playerIsLoser: true,
          loserAttribute: 'pyrus',
          margin: 10,
        ),
        contains('SUBTERRA'),
      );
    });

    test('does not apply from the margin on the card upwards', () {
      expect(
        closeLossEffectBlockedReason(
          condition: condition,
          playerIsLoser: true,
          loserAttribute: 'subterra',
          margin: 100,
        ),
        isNotNull,
      );
    });

    test('a card without conditions applies to the loser', () {
      expect(
        closeLossEffectBlockedReason(
          condition: null,
          playerIsLoser: true,
          loserAttribute: 'haos',
          margin: 500,
        ),
        isNull,
      );
    });
  });

  group('global gate bonuses', () {
    const forestFire = GateCard(
      key: 'forest_fire',
      name: 'Forest Fire',
      attributes: {},
      imagePath: '',
      descriptionEn: null,
      descriptionEs: null,
      cardClass: 'gold',
      hasEffect: true,
      persistent: 'global',
      effects: [
        {
          'type': 'used_pile_global_attribute_bonus',
          'attributes': ['pyrus', 'darkus', 'subterra'],
          'value': 50,
        },
      ],
    );

    test('gives its bonus only to the listed attributes', () {
      expect(forestFire.usedPileGlobalAttributeBonusFor('pyrus'), 50);
      expect(forestFire.usedPileGlobalAttributeBonusFor('Subterra'), 50);
      expect(forestFire.usedPileGlobalAttributeBonusFor('aquos'), 0);
    });

    test('exposes the bonus for the badge', () {
      expect(forestFire.hasUsedPileGlobalAttributeBonus, isTrue);
      final bonuses = forestFire.usedPileGlobalBonuses;
      expect(bonuses, hasLength(1));
      expect(bonuses.first.value, 50);
      expect(bonuses.first.attributes, ['pyrus', 'darkus', 'subterra']);
    });
  });
}
