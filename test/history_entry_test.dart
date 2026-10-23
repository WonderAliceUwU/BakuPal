import 'package:flutter_test/flutter_test.dart';

import 'package:bakugan_companion/main.dart';

void main() {
  Map<String, dynamic> json({bool? counted}) => {
    'id': '1',
    'seasonNumber': 2,
    'isTeamBattle': false,
    'playedAt': '2026-08-20T19:04:00',
    'winnerNames': ['Alice'],
    'players': [],
    if (counted != null) 'countedForElo': counted,
  };

  test('old history entries still count for the Elo', () {
    expect(MatchHistoryEntry.fromJson(json()).countedForElo, isTrue);
  });

  test('countedForElo is read and written', () {
    final entry = MatchHistoryEntry.fromJson(json(counted: false));
    expect(entry.countedForElo, isFalse);
    expect(entry.toJson()['countedForElo'], isFalse);
  });

  test('old PNG card and texture paths point at the WebP files', () {
    final card = MatchHistoryCardEntry.fromJson({
      'name': 'Fire Pit',
      'imagePath': 'assets/images/cards/base/BA133_GA_SM_fire_pit_F.png',
    });
    expect(
      card.imagePath,
      'assets/images/cards/base/BA133_GA_SM_fire_pit_F.webp',
    );
    expect(
      MatchHistoryCardEntry.fromJson({
        'name': 'Back',
        'imagePath': 'assets/images/cards/anverse.png',
      }).imagePath,
      'assets/images/cards/anverse.png',
    );

    final bakugan = MatchHistoryBakuganEntry.fromJson({
      'speciesName': 'Dragonoid',
      'attribute': 'pyrus',
      'gPower': 450,
      'modelPath':
          'assets/models/Season_1_Battle_Brawlers/Dragonoid/Dragonoid Stand.obj',
      'texturePath':
          'assets/models/Season_1_Battle_Brawlers/Dragonoid/Textures/Core/Pyrus Dragonoid.png',
      'imagePath': 'assets/images/bakugan/dragonoid/dragonoid_pyrus.png',
    });
    expect(
      bakugan.texturePath,
      'assets/models/Season_1_Battle_Brawlers/Dragonoid/Textures/Core/Pyrus Dragonoid.webp',
    );
    expect(
      bakugan.modelPath,
      'assets/models/Season_1_Battle_Brawlers/Dragonoid/Dragonoid Stand.obj',
    );
    expect(
      bakugan.imagePath,
      'assets/images/bakugan/dragonoid/dragonoid_pyrus.png',
    );
  });
}
