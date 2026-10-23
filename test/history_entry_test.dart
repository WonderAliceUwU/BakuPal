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
}
