import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Integrity checks for the card JSON files, which are edited by hand.
Map<String, Map<String, dynamic>> _load(String name) {
  final raw = File('assets/images/cards/$name.json').readAsStringSync();
  final cards = (jsonDecode(raw) as Map)['cards'] as Map;
  return {
    for (final entry in cards.entries)
      entry.key as String: Map<String, dynamic>.from(entry.value as Map),
  };
}

void main() {
  const attributes = {'pyrus', 'aquos', 'ventus', 'haos', 'darkus', 'subterra'};
  final files = {
    'cards': _load('cards'),
    'cards_expansion': _load('cards_expansion'),
  };

  test('card keys are unique across both files', () {
    final seen = <String>{};
    for (final cards in files.values) {
      for (final key in cards.keys) {
        expect(seen.add(key), isTrue, reason: 'duplicate card key "$key"');
      }
    }
  });

  test('every card has a name, a type, descriptions and an image file', () {
    for (final entry in files.entries) {
      for (final card in entry.value.entries) {
        final where = '${entry.key}/${card.key}';
        final data = card.value;
        expect(data['name']?.toString().trim(), isNotEmpty, reason: where);
        expect(
          {'gate', 'ability'}.contains(data['type']),
          isTrue,
          reason: '$where has type ${data['type']}',
        );
        // Cards flagged as incomplete in their own rules (text or image not
        // captured yet) are allowed to miss those fields.
        final rules = data['rules'];
        final flagged = rules is List
            ? rules
                  .whereType<Map>()
                  .map((rule) => rule['type'])
                  .whereType<String>()
                  .toSet()
            : <String>{};
        final descriptions = data['descriptions'];
        expect(descriptions, isA<Map>(), reason: where);
        if (!flagged.contains('incomplete_source_capture')) {
          expect(
            (descriptions as Map)['en']?.toString(),
            isNotEmpty,
            reason: '$where has no English description',
          );
        }
        if (!flagged.contains('missing_local_filename')) {
          expect(data['file']?.toString(), isNotEmpty, reason: where);
        }
      }
    }
  });

  test('attribute tables only use the six attributes', () {
    for (final entry in files.entries) {
      for (final card in entry.value.entries) {
        final table = card.value['attributes'];
        if (table is! Map) continue;
        for (final attribute in table.keys) {
          expect(
            attributes.contains(attribute),
            isTrue,
            reason: '${entry.key}/${card.key} uses "$attribute"',
          );
        }
      }
    }
  });

  test('every effect has a type', () {
    for (final entry in files.entries) {
      for (final card in entry.value.entries) {
        final effects = card.value['effects'];
        if (effects is! List) continue;
        for (final effect in effects) {
          expect(effect, isA<Map>(), reason: '${entry.key}/${card.key}');
          expect(
            (effect as Map)['type']?.toString(),
            isNotEmpty,
            reason: '${entry.key}/${card.key} has an effect without type',
          );
        }
      }
    }
  });

  test('persistent is "global" or "owner" and only on real cards', () {
    for (final entry in files.entries) {
      for (final card in entry.value.entries) {
        final persistent = card.value['persistent'];
        if (persistent == null) continue;
        expect(
          {'global', 'owner'}.contains(persistent),
          isTrue,
          reason: '${entry.key}/${card.key} has persistent "$persistent"',
        );
      }
    }
  });

  test('gate cards with the used-pile bonus effect are marked global', () {
    for (final entry in files.entries) {
      for (final card in entry.value.entries) {
        final effects = card.value['effects'];
        if (effects is! List) continue;
        final hasGlobalBonus = effects.any(
          (e) => e is Map && e['type'] == 'used_pile_global_attribute_bonus',
        );
        if (hasGlobalBonus) {
          expect(
            card.value['persistent'],
            'global',
            reason: '${entry.key}/${card.key} should be persistent: global',
          );
        }
      }
    }
  });
}
