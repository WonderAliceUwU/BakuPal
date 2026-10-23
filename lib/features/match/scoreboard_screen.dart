part of '../../main.dart';

enum MatchBakuganPileState { unused, standing, used, removed }

class ScoreboardScreen extends StatefulWidget {
  final List<PlayerData> players;
  final bool isTeamBattle;

  const ScoreboardScreen({
    super.key,
    required this.players,
    required this.isTeamBattle,
  });

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<ScoreboardScreen> {
  late List<int> scores;
  late AudioPlayer _sfxPlayer;
  final AudioPlayer _arenaPlayerA = AudioPlayer();
  final AudioPlayer _arenaPlayerB = AudioPlayer();
  final TextEditingController _matchCardNameController =
      TextEditingController();
  final FocusNode _matchCardNameFocusNode = FocusNode();
  Map<String, AbilityCard> _matchAbilityCards = {};
  // Gate cards that stay in effect while in a used pile (Forest Fire...), so
  // the game master can add them by hand.
  Map<String, GateCard> _globalGateCards = {};
  // Keys of owner-only gate cards staged as ability cards, so they are not
  // recorded as used abilities in the match history.
  final Set<String> _ownerGateCardKeys = {};
  bool _isLoadingMatchAbilityCards = true;
  List<String> _arenaPlaylist = const [];
  int _currentArenaTrackIndex = 0;
  int _currentArenaTrackLoopCount = 0;
  bool _useArenaPlayerA = true;
  bool _isArenaCrossfading = false;
  AbilityCard? _focusedMatchAbilityCard;
  GateCard? _focusedGlobalGateCard;
  int? _focusedMatchAbilityPlayerIndex;
  int? _focusedMatchAbilityIndex;
  late List<List<MatchPresentedAbility?>> _presentedMatchAbilities;
  final List<GateCard> _activeGlobalGateEffects = [];
  late List<List<MatchBakuganPileState>> _bakuganPileStates;
  late List<List<int?>> _bakuganStandOrder;
  int _nextStandOrder = 1;
  bool _isPauseMenuOpen = false;
  int? _matchWinnerIndex;
  String? _bakuganStayBannerText;
  int? _bakuganStayPlayerIndex;
  int? _bakuganStayBakuganIndex;
  bool _bakuganStayClosing = false;
  bool _isResolvingBakuganStay = false;
  final List<MatchBattleRecord> _battleHistory = [];
  final Map<String, Set<String>> _abilitiesUsedByPlayer = {};
  bool _showGameStartBanner = false;
  bool _showGameStartBannerContent = false;
  bool _hideGameStartBanner = false;
  Offset _gameStartBannerOffset = const Offset(-1.2, 0);

  bool selectionMode = false;
  BakuganVariant? leftBakugan;
  BakuganVariant? rightBakugan;
  PlayerData? leftPlayer;
  PlayerData? rightPlayer;
  int? leftBakuganIdx;
  int? rightBakuganIdx;
  late final MatchPauseController _matchPauseMenuController;

  @override
  void initState() {
    super.initState();
    _sfxPlayer = AudioPlayer();
    AppVolumeController.instance.register(_sfxPlayer);
    AppVolumeController.instance.register(_arenaPlayerA);
    AppVolumeController.instance.register(_arenaPlayerB);
    scores = widget.isTeamBattle
        ? [0, 0]
        : List.filled(widget.players.length, 0);
    _presentedMatchAbilities = List.generate(
      widget.players.length,
      (_) => List<MatchPresentedAbility?>.filled(3, null),
    );
    _bakuganPileStates = List.generate(
      widget.players.length,
      (playerIndex) => List<MatchBakuganPileState>.generate(
        3,
        (slotIndex) => slotIndex < widget.players[playerIndex].deck.length
            ? MatchBakuganPileState.unused
            : MatchBakuganPileState.used,
      ),
    );
    _bakuganStandOrder = List.generate(
      widget.players.length,
      (_) => List<int?>.filled(3, null),
    );
    _matchPauseMenuController = MatchPauseController(
      onOpen: _pauseArenaPlaylist,
      onAction: _handlePauseAction,
    );
    _matchPauseController.value = _matchPauseMenuController;
    _scoreboardOwnsPauseButton.value = true;
    _currentHelpTopic.addListener(_claimPauseButtonIfOnTop);
    AutomationController.instance.addListener(_onAutomationChanged);
    _loadMatchAbilityCards();
    _loadArenaPlaylistAndStart();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showGameStartOverlay());
    });
  }

  AudioPlayer get _activeArenaPlayer =>
      _useArenaPlayerA ? _arenaPlayerA : _arenaPlayerB;

  AudioPlayer get _inactiveArenaPlayer =>
      _useArenaPlayerA ? _arenaPlayerB : _arenaPlayerA;

  Future<void> _loadArenaPlaylistAndStart() async {
    try {
      await _bgMusicPlayer.stop();
      final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
        rootBundle,
      );
      final tracks =
          manifest
              .listAssets()
              .where(
                (asset) =>
                    asset.startsWith('assets/music/arena/') &&
                    asset.endsWith('.mp3') &&
                    !asset.endsWith('.DS_Store'),
              )
              .toList()
            ..sort();
      _arenaPlaylist = tracks.isNotEmpty
          ? tracks
          : const ['assets/music/arena/arena-1.mp3'];
      _arenaPlayerA.onPlayerComplete.listen((_) {
        if (_useArenaPlayerA) {
          _handleArenaTrackComplete();
        }
      });
      _arenaPlayerB.onPlayerComplete.listen((_) {
        if (!_useArenaPlayerA) {
          _handleArenaTrackComplete();
        }
      });
      await _playArenaTrack(0, immediate: true);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _setArenaPlayerVolume(AudioPlayer player, double volume) async {
    try {
      await _setAppPlayerBaseVolume(player, volume);
    } catch (_) {}
  }

  Future<void> _playArenaTrack(int index, {bool immediate = false}) async {
    if (_arenaPlaylist.isEmpty || _isArenaCrossfading) return;
    final normalizedIndex =
        (index % _arenaPlaylist.length + _arenaPlaylist.length) %
        _arenaPlaylist.length;
    final nextTrack = _arenaPlaylist[normalizedIndex];
    final nextPlayer = immediate ? _activeArenaPlayer : _inactiveArenaPlayer;
    final currentPlayer = _activeArenaPlayer;

    try {
      _isArenaCrossfading = true;
      await nextPlayer.stop();
      await nextPlayer.setReleaseMode(ReleaseMode.stop);
      await _setArenaPlayerVolume(nextPlayer, 0);
      await nextPlayer.play(AssetSource(nextTrack.replaceFirst('assets/', '')));

      if (immediate) {
        _currentArenaTrackIndex = normalizedIndex;
        _currentArenaTrackLoopCount = 0;
        await _setArenaPlayerVolume(nextPlayer, 0.4);
        _isArenaCrossfading = false;
        if (mounted) setState(() {});
        return;
      }

      const steps = 12;
      for (int step = 1; step <= steps; step++) {
        final t = step / steps;
        await _setArenaPlayerVolume(nextPlayer, 0.4 * t);
        await _setArenaPlayerVolume(currentPlayer, 0.4 * (1 - t));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await currentPlayer.stop();
      _useArenaPlayerA = !_useArenaPlayerA;
      _currentArenaTrackIndex = normalizedIndex;
      _currentArenaTrackLoopCount = 0;
      _isArenaCrossfading = false;
      if (mounted) setState(() {});
    } catch (_) {
      _isArenaCrossfading = false;
    }
  }

  Future<void> _handleArenaTrackComplete() async {
    if (_currentArenaTrackLoopCount == 0) {
      _currentArenaTrackLoopCount = 1;
      final activeTrack = _arenaPlaylist[_currentArenaTrackIndex];
      try {
        await _activeArenaPlayer.stop();
        await _activeArenaPlayer.play(
          AssetSource(activeTrack.replaceFirst('assets/', '')),
        );
        await _setArenaPlayerVolume(_activeArenaPlayer, 0.4);
      } catch (_) {}
      if (mounted) setState(() {});
      return;
    }
    await _playArenaTrack(_currentArenaTrackIndex + 1);
  }

  Future<void> _pauseArenaPlaylist() async {
    try {
      await _arenaPlayerA.pause();
      await _arenaPlayerB.pause();
    } catch (_) {}
  }

  Future<void> _resumeArenaPlaylist() async {
    try {
      await _activeArenaPlayer.resume();
      await _setArenaPlayerVolume(_activeArenaPlayer, 0.4);
    } catch (_) {}
  }

  Future<void> _toggleArenaMute() async {
    await AppVolumeController.instance.toggleMute();
  }

  Future<void> _playMatchWinSound() async {
    try {
      await _arenaPlayerA.stop();
      await _arenaPlayerB.stop();
      await _bgMusicPlayer.stop();
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource('sound/win_match.mp3'));
    } catch (_) {}
  }

  Future<void> _playRevealSfx(String assetName) async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource('sound/$assetName'));
    } catch (_) {}
  }

  Future<void> _showGameStartOverlay() async {
    if (!mounted) return;

    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    setState(() {
      _showGameStartBanner = true;
      _showGameStartBannerContent = false;
      _hideGameStartBanner = false;
      _gameStartBannerOffset = const Offset(-1.2, 0);
    });

    unawaited(_playRevealSfx('game_start.wav'));

    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;

    setState(() {
      _showGameStartBannerContent = true;
      _gameStartBannerOffset = Offset.zero;
    });

    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;

    setState(() {
      _showGameStartBannerContent = false;
      _hideGameStartBanner = true;
      _gameStartBannerOffset = const Offset(1.2, 0);
    });

    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;

    setState(() {
      _showGameStartBanner = false;
      _showGameStartBannerContent = false;
      _hideGameStartBanner = false;
      _gameStartBannerOffset = const Offset(-1.2, 0);
    });
  }

  Future<void> _loadMatchAbilityCards() async {
    try {
      const jsonPaths = [
        'assets/images/cards/cards.json',
        'assets/images/cards/cards_expansion.json',
      ];
      final Map<String, dynamic> cards = <String, dynamic>{};
      for (final jsonPath in jsonPaths) {
        final String rawJson = await rootBundle.loadString(jsonPath);
        final decodedJson = jsonDecode(rawJson);
        if (decodedJson is! Map) continue;
        final decoded = Map<String, dynamic>.from(decodedJson);
        final cardsNode = decoded['cards'];
        if (cardsNode is! Map) continue;
        cards.addAll(Map<String, dynamic>.from(cardsNode));
      }
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest
          .listAssets()
          .where(
            (asset) =>
                asset.startsWith('assets/images/cards/') &&
                asset != 'assets/images/cards/anverse.png' &&
                asset.endsWith('.webp'),
          )
          .toList();

      final Map<String, AbilityCard> loadedAbilityCards = {};
      final Map<String, GateCard> loadedGlobalGateCards = {};
      for (final entry in cards.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value is! Map) continue;
        final data = Map<String, dynamic>.from(value);
        final cardType = (data['type'] ?? '').toString().trim().toLowerCase();
        if (cardType == 'gate') {
          final persistent = data['persistent']?.toString();
          if (persistent != 'global' && persistent != 'owner') continue;
          final gate = _gateCardFromData(key, data, assets);
          if (persistent == 'global') {
            loadedGlobalGateCards[key] = gate;
          } else {
            // Owner-only gate effects are staged in the owner's ability slots.
            _ownerGateCardKeys.add(key);
            loadedAbilityCards[key] = AbilityCard(
              key: gate.key,
              name: gate.name,
              imagePath: gate.imagePath,
              descriptionEn: gate.descriptionEn,
              descriptionEs: gate.descriptionEs,
              attributes: const {},
              cardClass: gate.cardClass,
              timings: const {},
              effects: gate.effects,
              persistent: persistent,
            );
          }
          continue;
        }
        if (cardType != 'ability') {
          continue;
        }

        final String name = (data['name'] ?? '').toString().trim();
        final String? fileName = data['file']?.toString();
        final String cardClass = (data['card_class'] ?? 'blue')
            .toString()
            .toLowerCase();
        final descriptionsRaw = data['descriptions'];
        final Map<String, dynamic> descriptions =
            descriptionsRaw is Map<String, dynamic>
            ? descriptionsRaw
            : descriptionsRaw is Map
            ? Map<String, dynamic>.from(descriptionsRaw)
            : const {};
        final String? descriptionEn = descriptions['en']?.toString();
        final String? descriptionEs = descriptions['es']?.toString();
        final attributesRaw = data['attributes'];
        final Map<String, int> attributes = <String, int>{};
        if (attributesRaw is Map) {
          for (final attrEntry in attributesRaw.entries) {
            final attrKey = attrEntry.key.toString().toLowerCase();
            final attrValue = attrEntry.value;
            if (attrValue is num) {
              attributes[attrKey] = attrValue.toInt();
            }
          }
        }
        final effectsRaw = data['effects'];
        final List<dynamic> effects = effectsRaw is List
            ? List<dynamic>.from(effectsRaw)
            : const [];
        final rulesRaw = data['rules'];
        final List<dynamic> rules = rulesRaw is List
            ? List<dynamic>.from(rulesRaw)
            : const [];
        final Set<String> timings = <String>{};
        final timingsRaw = data['timings'];
        if (timingsRaw is List) {
          for (final timing in timingsRaw) {
            timings.add(timing.toString().toLowerCase());
          }
        }
        for (final rule in rules) {
          if (rule is Map && rule['timing'] != null) {
            timings.add(rule['timing'].toString().toLowerCase());
          }
        }
        for (final effect in effects) {
          if (effect is Map && effect['timing'] != null) {
            timings.add(effect['timing'].toString().toLowerCase());
          }
        }

        final imagePath = _matchCardImagePath(
          cardKey: key,
          cardName: name,
          assetPaths: assets,
          fileName: fileName,
        );
        loadedAbilityCards[key] = AbilityCard(
          key: key,
          name: name,
          persistent: data['persistent']?.toString(),
          imagePath: imagePath ?? 'assets/images/cards/anverse.png',
          descriptionEn: descriptionEn,
          descriptionEs: descriptionEs,
          attributes: attributes,
          cardClass: cardClass,
          timings: timings,
          effects: effects,
        );
      }

      if (!mounted) return;
      setState(() {
        _matchAbilityCards = loadedAbilityCards;
        _globalGateCards = loadedGlobalGateCards;
        _isLoadingMatchAbilityCards = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMatchAbilityCards = false;
      });
    }
  }

  GateCard _gateCardFromData(
    String key,
    Map<String, dynamic> data,
    List<String> assets,
  ) {
    final effectsRaw = data['effects'];
    final effects = effectsRaw is List
        ? List<dynamic>.from(effectsRaw)
        : const <dynamic>[];
    final name = (data['name'] ?? '').toString().trim();
    final descriptionsRaw = data['descriptions'];
    final descriptions = descriptionsRaw is Map
        ? Map<String, dynamic>.from(descriptionsRaw)
        : const <String, dynamic>{};
    final attributes = <String, int>{};
    final attributesRaw = data['attributes'];
    if (attributesRaw is Map) {
      for (final attr in attributesRaw.entries) {
        final amount = attr.value;
        if (amount is num) {
          attributes[attr.key.toString().toLowerCase()] = amount.toInt();
        }
      }
    }
    return GateCard(
      key: key,
      name: name,
      persistent: data['persistent']?.toString(),
      attributes: attributes,
      imagePath:
          _matchCardImagePath(
            cardKey: key,
            cardName: name,
            assetPaths: assets,
            fileName: data['file']?.toString(),
          ) ??
          'assets/images/cards/anverse.png',
      descriptionEn: descriptions['en']?.toString(),
      descriptionEs: descriptions['es']?.toString(),
      cardClass: (data['card_class'] ?? 'silver').toString().toLowerCase(),
      hasEffect: effects.isNotEmpty,
      effects: effects,
    );
  }

  List<GateCard> _rankGlobalGateCardMatches(String input) {
    final query = _normalizeCardLookup(input);
    final available = _globalGateCards.values
        .where(
          (card) =>
              !_activeGlobalGateEffects.any((active) => active.key == card.key),
        )
        .toList();
    if (query.isEmpty) return available;

    final ranked =
        available
            .map((card) {
              final name = _normalizeCardLookup(card.name);
              final key = _normalizeCardLookup(card.key);
              int score = 0;
              if (name == query) score += 1000;
              if (key == query) score += 900;
              if (name.startsWith(query)) score += 400;
              if (key.startsWith(query)) score += 300;
              if (name.contains(query)) score += 150;
              if (key.contains(query)) score += 100;
              return (card: card, score: score);
            })
            .where((entry) => entry.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return ranked.map((entry) => entry.card).toList();
  }

  Future<void> _openGlobalGateEffectPicker() async {
    if (_isLoadingMatchAbilityCards || selectionMode) return;

    final selected = await _showMatchCardSearchDialog<GateCard>(
      title: 'Add Global Gate Effect',
      subtitle:
          'Choose a gate card that stays in effect for every player while it is in a used pile.',
      hint: 'Example: Forest Fire',
      notFoundText: 'Gate card not found or already in effect.',
      confirmLabel: 'ADD',
      rank: _rankGlobalGateCardMatches,
      nameOf: (card) => card.name,
      keyOf: (card) => card.key,
    );

    if (selected == null || !mounted) return;
    setState(() => _activeGlobalGateEffects.add(selected));
  }

  bool _isMatchStageAbilityCard(AbilityCard card) {
    return card.isMatchStageCard;
  }

  List<AbilityCard> _rankMatchAbilityCardMatches(String input) {
    final query = _normalizeCardLookup(input);
    if (query.isEmpty) {
      return _matchAbilityCards.values
          .where(_isMatchStageAbilityCard)
          .take(8)
          .toList();
    }

    final ranked =
        _matchAbilityCards.values
            .where(_isMatchStageAbilityCard)
            .map((card) {
              final normalizedName = _normalizeCardLookup(card.name);
              final normalizedKey = _normalizeCardLookup(card.key);
              int score = 0;
              if (normalizedName == query) score += 1000;
              if (normalizedKey == query) score += 900;
              if (normalizedName.startsWith(query)) score += 400;
              if (normalizedKey.startsWith(query)) score += 300;
              if (normalizedName.contains(query)) score += 150;
              if (normalizedKey.contains(query)) score += 100;
              return (card: card, score: score);
            })
            .where((entry) => entry.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return ranked.map((entry) => entry.card).toList();
  }

  // Search dialog shared by the ability and global gate pickers: a text field
  // with a ranked suggestion list; picking a suggestion (or typing an exact
  // name/key) returns that card.
  Future<T?> _showMatchCardSearchDialog<T extends Object>({
    required String title,
    required String subtitle,
    required String hint,
    required String notFoundText,
    required String confirmLabel,
    required List<T> Function(String input) rank,
    required String Function(T card) nameOf,
    required String Function(T card) keyOf,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _matchCardNameController.clear();

    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final query = _normalizeCardLookup(_matchCardNameController.text);
              final match = query.isEmpty
                  ? null
                  : rank(_matchCardNameController.text)
                        .where(
                          (card) =>
                              _normalizeCardLookup(nameOf(card)) == query ||
                              _normalizeCardLookup(keyOf(card)) == query,
                        )
                        .firstOrNull;
              if (match == null) {
                setDialogState(() => errorText = notFoundText);
                return;
              }
              Navigator.of(context).pop(match);
            }

            return Dialog(
              backgroundColor: const Color(0xFF111318),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              child: Container(
                width: 540,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                    const SizedBox(height: 20),
                    RawAutocomplete<T>(
                      textEditingController: _matchCardNameController,
                      focusNode: _matchCardNameFocusNode,
                      displayStringForOption: nameOf,
                      optionsBuilder: (textEditingValue) {
                        return rank(textEditingValue.text);
                      },
                      onSelected: (option) => Navigator.of(context).pop(option),
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: true,
                              onChanged: (_) {
                                if (errorText != null) {
                                  setDialogState(() => errorText = null);
                                }
                              },
                              onSubmitted: (_) => submit(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: InputDecoration(
                                hintText: hint,
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                                errorText: errorText,
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.06),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                      optionsViewBuilder: (context, onSelected, options) {
                        final matches = options.toList();
                        if (matches.isEmpty) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: const Color(0xFF171B22),
                            elevation: 12,
                            borderRadius: BorderRadius.circular(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 540,
                                maxHeight: 260,
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                shrinkWrap: true,
                                itemCount: matches.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Colors.white12,
                                ),
                                itemBuilder: (context, index) {
                                  final card = matches[index];
                                  return InkWell(
                                    onTap: () => onSelected(card),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              nameOf(card),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            keyOf(card),
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'CANCEL',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openMatchAbilityPrompt(int playerIndex, int slotIndex) async {
    if (_isLoadingMatchAbilityCards || selectionMode) return;
    if (_presentedMatchAbilities[playerIndex][slotIndex] != null) return;

    final selectedCard = await _showMatchCardSearchDialog<AbilityCard>(
      title: 'Present Match Ability',
      subtitle:
          'Choose an ability card with no battle timing to stage it on the match screen.',
      hint: 'Example: Marucho\'s Throw',
      notFoundText: 'Ability card not found or not available outside battle.',
      confirmLabel: 'PRESENT',
      rank: _rankMatchAbilityCardMatches,
      nameOf: (card) => card.name,
      keyOf: (card) => card.key,
    );

    if (selectedCard != null) {
      _presentMatchAbility(playerIndex, slotIndex, selectedCard);
    }
  }

  void _presentMatchAbility(int playerIndex, int slotIndex, AbilityCard card) {
    if (_presentedMatchAbilities[playerIndex][slotIndex] != null) return;

    _playRevealSfx('ability_reveal.wav');
    final playerName = widget.players[playerIndex].name;
    if (!_ownerGateCardKeys.contains(card.key)) {
      _abilitiesUsedByPlayer
          .putIfAbsent(playerName, () => <String>{})
          .add(card.name);
    }

    setState(() {
      _presentedMatchAbilities[playerIndex][slotIndex] = MatchPresentedAbility(
        card: card,
      );
      _focusedMatchAbilityCard = card;
      _focusedGlobalGateCard = null;
      _focusedMatchAbilityPlayerIndex = playerIndex;
      _focusedMatchAbilityIndex = slotIndex;
    });
  }

  void _focusPresentedAbility(int playerIndex, int abilityIndex) {
    final presented = _presentedMatchAbilities[playerIndex][abilityIndex];
    if (presented == null) return;

    setState(() {
      _focusedMatchAbilityCard = presented.card;
      _focusedGlobalGateCard = null;
      _focusedMatchAbilityPlayerIndex = playerIndex;
      _focusedMatchAbilityIndex = abilityIndex;
    });
  }

  void _togglePresentedAbility(int playerIndex, int abilityIndex) {
    final current = _presentedMatchAbilities[playerIndex][abilityIndex];
    if (current == null) return;

    setState(() {
      _presentedMatchAbilities[playerIndex][abilityIndex] = current.copyWith(
        isActive: !current.isActive,
      );
    });
  }

  void _returnFocusedMatchAbilityToUnusedPile() {
    final playerIndex = _focusedMatchAbilityPlayerIndex;
    final abilityIndex = _focusedMatchAbilityIndex;
    if (playerIndex == null || abilityIndex == null) return;

    setState(() {
      _presentedMatchAbilities[playerIndex][abilityIndex] = null;
      _focusedMatchAbilityCard = null;
      _focusedGlobalGateCard = null;
      _focusedMatchAbilityPlayerIndex = null;
      _focusedMatchAbilityIndex = null;
    });
  }

  void _focusGlobalGateEffect(GateCard card) {
    setState(() {
      _focusedMatchAbilityCard = null;
      _focusedMatchAbilityPlayerIndex = null;
      _focusedMatchAbilityIndex = null;
      _focusedGlobalGateCard = card;
    });
  }

  void _removeFocusedGlobalGateEffect() {
    final card = _focusedGlobalGateCard;
    if (card == null) return;

    setState(() {
      _activeGlobalGateEffects.remove(card);
      _focusedGlobalGateCard = null;
    });
  }

  Widget _buildArenaPlaylistBar() {
    final trackLabel = _arenaPlaylist.isEmpty
        ? 'LOADING...'
        : _arenaPlaylist[_currentArenaTrackIndex]
              .split('/')
              .last
              .replaceAll('.mp3', '')
              .replaceAll('-', ' ')
              .toUpperCase();

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.12),
          child: Container(
            width: 600,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.skewX(0.12),
              child: Row(
                children: [
                  _buildPlaylistIconButton(
                    icon: Icons.skip_previous,
                    onTap: () => _playArenaTrack(_currentArenaTrackIndex - 1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ARENA PLAYLIST',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          trackLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListenableBuilder(
                    listenable: AppVolumeController.instance,
                    builder: (context, _) => _buildPlaylistIconButton(
                      icon:
                          AppVolumeController.instance.isMuted ||
                              AppVolumeController.instance.volume == 0
                          ? Icons.volume_off
                          : Icons.volume_up,
                      onTap: _toggleArenaMute,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildPlaylistIconButton(
                    icon: Icons.skip_next,
                    onTap: () => _playArenaTrack(_currentArenaTrackIndex + 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildMatchAbilityOverlay() {
    final card = _focusedMatchAbilityCard;
    final gateCard = _focusedGlobalGateCard;
    if (card == null && gateCard == null) return const SizedBox.shrink();
    final imagePath = gateCard?.imagePath ?? card!.imagePath;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InteractiveCard(
                  imagePath: imagePath,
                  width: 380,
                  onTap: () {
                    setState(() {
                      _focusedMatchAbilityCard = null;
                      _focusedGlobalGateCard = null;
                      _focusedMatchAbilityPlayerIndex = null;
                      _focusedMatchAbilityIndex = null;
                    });
                  },
                ),
                const SizedBox(height: 46),
                gateCard != null
                    ? _buildGlobalGateDescriptionPanel(gateCard)
                    : _buildMatchAbilityDescriptionPanel(card!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchAbilityDescriptionPanel(AbilityCard card) {
    final hasDescription =
        (card.descriptionEn?.trim().isNotEmpty ?? false) ||
        (card.descriptionEs?.trim().isNotEmpty ?? false);
    if (!hasDescription) return const SizedBox.shrink();

    final accentColor =
        _abilityDescriptionAccentColors[card.cardClass] ??
        _abilityDescriptionAccentColors['blue']!;

    return FramedDescriptionPanel(
      width: 620,
      title: card.name,
      esText: card.descriptionFor(LanguageController.instance.cardLanguage),
      maxHeight: 300,
      frameGradient:
          _abilityDescriptionBorderGradients[card.cardClass] ??
          _abilityDescriptionBorderGradients['blue']!,
      accentColor: accentColor,
      headerAction: DescriptionHeaderActionButton(
        accentColor: accentColor,
        onTap: _returnFocusedMatchAbilityToUnusedPile,
      ),
    );
  }

  Widget _buildGlobalGateDescriptionPanel(GateCard card) {
    final hasDescription =
        (card.descriptionEn?.trim().isNotEmpty ?? false) ||
        (card.descriptionEs?.trim().isNotEmpty ?? false);
    if (!hasDescription) return const SizedBox.shrink();

    // Global ability cards reuse this panel, so fall back to the ability
    // palette before the neutral silver one.
    final accentColor =
        _gateDescriptionAccentColors[card.cardClass] ??
        _abilityDescriptionAccentColors[card.cardClass] ??
        _gateDescriptionAccentColors['silver']!;

    return FramedDescriptionPanel(
      width: 620,
      title: card.name,
      esText: card.descriptionFor(LanguageController.instance.cardLanguage),
      maxHeight: 300,
      frameGradient:
          _gateDescriptionBorderGradients[card.cardClass] ??
          _abilityDescriptionBorderGradients[card.cardClass] ??
          _gateDescriptionBorderGradients['silver']!,
      accentColor: accentColor,
      headerAction: DescriptionHeaderActionButton(
        accentColor: accentColor,
        onTap: _removeFocusedGlobalGateEffect,
      ),
    );
  }

  Widget _buildProfileAbilityRail(int playerIndex, {required bool alignRight}) {
    final abilities = _presentedMatchAbilities[playerIndex];
    const int maxSlots = 3;

    return SizedBox(
      width: 530,
      height: 104,
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: alignRight ? TextDirection.rtl : TextDirection.ltr,
          children: List.generate(maxSlots, (index) {
            final presented = abilities[index];
            final hasCard = presented != null;

            final isHidden =
                hasCard &&
                _focusedMatchAbilityCard != null &&
                _focusedMatchAbilityPlayerIndex == playerIndex &&
                _focusedMatchAbilityIndex == index;

            final isDisabled = _isLoadingMatchAbilityCards || selectionMode;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubic,
              width: isHidden ? 0 : 90,
              height: 90,
              margin: EdgeInsets.symmetric(
                horizontal: isHidden ? 0 : _matchAbilityRailSpacing / 2,
              ),
              child: IgnorePointer(
                ignoring: isHidden,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  opacity: isHidden ? 0 : 1,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    scale: isHidden ? 0.86 : 1,
                    child: hasCard
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () =>
                                _togglePresentedAbility(playerIndex, index),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: presented.isActive ? 1.0 : 0.48,
                              child: Align(
                                alignment: Alignment.center,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 320),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    final rotate = Tween<double>(
                                      begin: pi / 2,
                                      end: 0,
                                    ).animate(animation);

                                    return AnimatedBuilder(
                                      animation: rotate,
                                      child: child,
                                      builder: (context, child) {
                                        return Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.identity()
                                            ..setEntry(3, 2, 0.0015)
                                            ..rotateY(rotate.value),
                                          child: child,
                                        );
                                      },
                                    );
                                  },
                                  child: InteractiveCard(
                                    key: ValueKey(
                                      'ability_${playerIndex}_${index}_${presented.card.key}',
                                    ),
                                    imagePath: presented.card.imagePath,
                                    width: 90,
                                    onTap: () => _focusPresentedAbility(
                                      playerIndex,
                                      index,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Opacity(
                            opacity: isDisabled ? 0.4 : 1.0,
                            child: IgnorePointer(
                              ignoring: isDisabled,
                              child: InteractiveCard(
                                key: ValueKey('anverse_${playerIndex}_$index'),
                                imagePath: 'assets/images/cards/anverse.png',
                                width: 90,
                                onTap: () =>
                                    _openMatchAbilityPrompt(playerIndex, index),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  static const double _globalGateBonusWidth = 78;
  // Width / height of the card frame images in assets/frames.
  static const double _gateFrameAspectRatio = 842 / 1122;

  // "+50" and the attribute logos shown to the left of a global gate card.
  Widget _buildGlobalGateBonusBadge(GateCard card) =>
      GlobalGateBonusBadge(card: card, width: _globalGateBonusWidth);

  Widget _buildGlobalGateAddButton() {
    final hasAvailable = _globalGateCards.values.any(
      (card) =>
          !_activeGlobalGateEffects.any((active) => active.key == card.key),
    );
    // A manual tool: hidden in auto mode, where the app applies the card
    // effects itself (switch to assisted to get it back).
    if (selectionMode ||
        !hasAvailable ||
        !AutomationController.instance.level.showsManualTools) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _matchAbilityRailSpacing / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openGlobalGateEffectPicker,
        // An empty silver card frame with a "+" in its window, faded so it reads
        // as a placeholder where the next gate effect card would go.
        child: SizedBox(
          width: 90,
          height: 90,
          // Same box the rail cards use: the frame is scaled to the 90 px
          // height, like the card images next to it.
          child: Center(
            child: SizedBox(
              height: 90,
              child: Opacity(
                opacity: 0.45,
                child: AspectRatio(
                  aspectRatio: _gateFrameAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/frames/Final Silver Frame.png',
                        fit: BoxFit.fill,
                      ),
                      const Align(
                        alignment: Alignment(-0.06, -0.06),
                        child: Icon(Icons.add, color: Colors.white, size: 36),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Presented ability cards that affect every player (Power Card Alpha...) are
  // also shown in the centre rail, next to the active gate effects. They stay
  // in their owner's slot too; tapping either one focuses the same card.
  List<({int playerIndex, int slotIndex, MatchPresentedAbility presented})>
  _globalPresentedAbilities() {
    return [
      for (int p = 0; p < _presentedMatchAbilities.length; p++)
        for (int i = 0; i < _presentedMatchAbilities[p].length; i++)
          if (_presentedMatchAbilities[p][i]?.card.persistent == 'global')
            (
              playerIndex: p,
              slotIndex: i,
              presented: _presentedMatchAbilities[p][i]!,
            ),
    ];
  }

  Widget _buildGlobalAbilityRailItem(
    ({int playerIndex, int slotIndex, MatchPresentedAbility presented}) entry,
  ) {
    final isHidden =
        _focusedMatchAbilityCard != null &&
        _focusedMatchAbilityPlayerIndex == entry.playerIndex &&
        _focusedMatchAbilityIndex == entry.slotIndex;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: isHidden ? 0 : 90,
      height: 90,
      margin: EdgeInsets.symmetric(
        horizontal: isHidden ? 0 : _matchAbilityRailSpacing / 2,
      ),
      child: IgnorePointer(
        ignoring: isHidden,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isHidden ? 0 : (entry.presented.isActive ? 1.0 : 0.48),
          child: InteractiveCard(
            key: ValueKey(
              'global_ability_${entry.playerIndex}_${entry.slotIndex}_${entry.presented.card.key}',
            ),
            imagePath: entry.presented.card.imagePath,
            width: 90,
            onTap: () =>
                _focusPresentedAbility(entry.playerIndex, entry.slotIndex),
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalGateEffectRail() {
    final globalAbilities = _globalPresentedAbilities();
    if (_activeGlobalGateEffects.isEmpty &&
        _globalGateCards.isEmpty &&
        globalAbilities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 110),
        child: SizedBox(
          height: 104,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...List.generate(_activeGlobalGateEffects.length, (index) {
                final card = _activeGlobalGateEffects[index];
                final isHidden = _focusedGlobalGateCard == card;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  width: isHidden ? 0 : 90 + _globalGateBonusWidth,
                  height: 90,
                  margin: EdgeInsets.symmetric(
                    horizontal: isHidden ? 0 : _matchAbilityRailSpacing / 2,
                  ),
                  child: IgnorePointer(
                    ignoring: isHidden,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: isHidden ? 0 : 1,
                      // Not clipped, so the card's hover zoom is not cut off;
                      // the row is invisible while it collapses anyway.
                      child: OverflowBox(
                        minWidth: 0,
                        maxWidth: 90 + _globalGateBonusWidth,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildGlobalGateBonusBadge(card),
                            InteractiveCard(
                              key: ValueKey(
                                'global_match_gate_${card.key}_$index',
                              ),
                              imagePath: card.imagePath,
                              width: 90,
                              onTap: () => _focusGlobalGateEffect(card),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              for (final entry in globalAbilities)
                _buildGlobalAbilityRailItem(entry),
              _buildGlobalGateAddButton(),
            ],
          ),
        ),
      ),
    );
  }

  // STAY shows up as one more tile after the player's three Bakugan slots.
  Widget Function(double slotSize)? _stayTileBuilder(int playerIndex) {
    if (selectionMode || _editMode || !_canUseBakuganStay(playerIndex)) {
      return null;
    }
    return (slotSize) => BakuganStayTile(
      size: slotSize,
      onPressed: () => _triggerBakuganStay(playerIndex),
    );
  }

  Widget? _buildProfileAbilityOverlay(int playerIndex, {required bool above}) {
    if (selectionMode || _editMode) {
      return null;
    }
    final alignRight = playerIndex.isOdd;

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: alignRight ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildProfileAbilityRail(playerIndex, alignRight: alignRight),
        ],
      ),
    );
  }

  Widget _buildBakuganStayOverlay() {
    final text = _bakuganStayBannerText;
    final playerIndex = _bakuganStayPlayerIndex;
    final bakuganIndex = _bakuganStayBakuganIndex;
    if (text == null || playerIndex == null || bakuganIndex == null) {
      return const SizedBox.shrink();
    }

    final player = widget.players[playerIndex];
    if (bakuganIndex >= player.deck.length) {
      return const SizedBox.shrink();
    }
    final variant = player.deck[bakuganIndex];
    final isMirrored = playerIndex.isOdd;
    final title = text == 'REMOVED'
        ? '${variant.speciesName.toUpperCase()} REMOVED FROM BATTLE'
        : "${player.name.toUpperCase()} STAYS!";

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          opacity: _bakuganStayClosing ? 0 : 1,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            offset: _bakuganStayClosing ? const Offset(0, -0.08) : Offset.zero,
            child: Container(
              color: Colors.black.withValues(alpha: 0.72),
              child: BattleResultShowcase(
                title: title,
                previewChild: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: _abilityPresentationWidth,
                      height: _abilityPresentationHeight,
                      child: Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 500,
                          height: 500,
                          child: BakuganPreview(
                            variant: variant,
                            isLarge: true,
                            autoRotate: false,
                            theta: isMirrored ? 40 : -40,
                            phi: 75,
                            disableInteraction: true,
                            speciesName: variant.speciesName,
                            showGPower: false,
                            mirrorImage: isMirrored,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _hideBakuganResultOverlay() async {
    if (!mounted) return;
    setState(() {
      _bakuganStayClosing = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() {
      _bakuganStayBannerText = null;
      _bakuganStayPlayerIndex = null;
      _bakuganStayBakuganIndex = null;
      _bakuganStayClosing = false;
    });
  }

  Future<void> _playCharacterSelectMusic() async {
    try {
      await _arenaPlayerA.stop();
      await _arenaPlayerB.stop();
      await _bgMusicPlayer.stop();
      await _bgMusicPlayer.play(AssetSource('music/menu/Menu.mp3'));
    } catch (_) {}
  }

  Future<void> _openPauseMenu() async {
    if (_isPauseMenuOpen) return;
    _isPauseMenuOpen = true;
    await _pauseArenaPlaylist();
    if (!mounted) return;

    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Pause Menu',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),
              Center(
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.skewX(-0.12),
                    child: SizedBox(
                      width: 520,
                      height: 720,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF7B6330),
                              Color(0xFFE5D2A6),
                              Color(0xFF394352),
                              Color(0xFF151A22),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.65),
                              blurRadius: 32,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.12),
                              blurRadius: 34,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFF090D13),
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: GridPainter(
                                    color: Colors.cyanAccent.withValues(
                                      alpha: 0.06,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.05),
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.15),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 22,
                                  ),
                                  child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.skewX(0.12),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 360,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 84,
                                              height: 84,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.blueAccent
                                                        .withValues(alpha: 0.9),
                                                    Colors.cyanAccent
                                                        .withValues(alpha: 0.7),
                                                  ],
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.cyanAccent
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 20,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.75),
                                                  width: 2.5,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.pause_rounded,
                                                color: Colors.white,
                                                size: 42,
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            const Text(
                                              'PAUSED',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 40,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 5,
                                                fontStyle: FontStyle.italic,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.blueAccent,
                                                    blurRadius: 18,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Choose your next move',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.68,
                                                ),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.04,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.09),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  BakuganButton(
                                                    text: 'Resume',
                                                    icon: Icons
                                                        .play_arrow_rounded,
                                                    iconOnly: false,
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop('resume'),
                                                    width: 340,
                                                    height: 68,
                                                  ),
                                                  const SizedBox(height: 10),
                                                  BakuganButton(
                                                    text: 'Restart',
                                                    icon: Icons
                                                        .restart_alt_rounded,
                                                    iconOnly: false,
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop('selection'),
                                                    width: 340,
                                                    height: 68,
                                                    color: Colors.orangeAccent,
                                                  ),
                                                  const SizedBox(height: 10),
                                                  BakuganButton(
                                                    text: 'Exit to menu',
                                                    icon: Icons.home_rounded,
                                                    iconOnly: false,
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop('main_menu'),
                                                    width: 340,
                                                    height: 68,
                                                    color: Colors.redAccent,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'ESC to resume',
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

    _isPauseMenuOpen = false;
    if (!mounted) return;

    if (action == 'main_menu') {
      Navigator.of(context).pushAndRemoveUntil(
        _fadeRoute(const MainMenuScreen()),
        (route) => false,
      );
      return;
    }

    if (action == 'selection') {
      await _playCharacterSelectMusic();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    await _resumeArenaPlaylist();
  }

  Future<void> _handlePauseAction(String action) async {
    if (!mounted) return;

    if (action == 'main_menu') {
      Navigator.of(context).pushAndRemoveUntil(
        _fadeRoute(const MainMenuScreen()),
        (route) => false,
      );
      return;
    }

    if (action == 'selection') {
      await _playCharacterSelectMusic();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    await _resumeArenaPlaylist();
  }

  // Only in auto mode is the match won by itself at 3 points; in manual and
  // assisted the game master confirms it with the WIN? button next to the score.
  // After a win is undone, the automatic win stays off for the rest of the
  // match (the WIN? button is used instead), also if the mode changes.
  bool _autoWinSuspended = false;

  bool get _declaresMatchWinnerAutomatically =>
      !_autoWinSuspended &&
      AutomationController.instance.level == AutomationLevel.auto;

  void _addPoint(int index, {bool playPointSound = true}) async {
    bool didWinMatch = false;
    setState(() {
      if (scores[index] < 3) {
        scores[index]++;
        if (scores[index] >= 3 && _declaresMatchWinnerAutomatically) {
          didWinMatch = true;
          _setMatchWinnerState(index);
        }
      }
    });
    if (playPointSound) {
      unawaited(_playPointCaptureSound());
    }
    if (didWinMatch) {
      await _recordMatchResult(index);
    }
  }

  void _setMatchWinnerState(int index) {
    _matchWinnerIndex = index;
    selectionMode = false;
    leftBakugan = null;
    rightBakugan = null;
    leftPlayer = null;
    rightPlayer = null;
    leftBakuganIdx = null;
    rightBakuganIdx = null;
  }

  // The leaderboard and history as they were before the result was recorded,
  // so the win can be undone.
  LeaderboardStore? _storeBeforeResult;

  Future<void> _recordMatchResult(int index, {bool awaitSound = true}) async {
    _storeBeforeResult = await LeaderboardRepository.instance.loadStore();
    await _recordLeaderboardMatch(index);
    // The match counted for the Elo if someone's matches went up (it does not
    // when the Elo is paused or the registered players have not started the
    // season).
    final after = await LeaderboardRepository.instance.loadStore();
    final countedForElo =
        _totalEloMatches(after) > _totalEloMatches(_storeBeforeResult ?? after);
    await _recordMatchHistory(index, countedForElo: countedForElo);
    if (awaitSound) {
      await _playMatchWinSound();
    } else {
      unawaited(_playMatchWinSound());
    }
  }

  // Takes a declared win back (KEEP BRAWLING): the match goes on, the records are restored and
  // the automatic win is switched off for the rest of the match, so it is not
  // declared again by itself (the WIN? button comes back).
  Future<void> _undoMatchWin() async {
    if (_matchWinnerIndex == null) return;
    final snapshot = _storeBeforeResult;
    if (snapshot != null) {
      await LeaderboardRepository.instance.restoreStore(snapshot);
      _storeBeforeResult = null;
    }
    if (!mounted) return;
    setState(() {
      _autoWinSuspended = true;
      _matchWinnerIndex = null;
    });
    unawaited(_playArenaTrack(_currentArenaTrackIndex, immediate: true));
  }

  // Manual mode: the game master declares the winner.
  Future<void> _declareMatchWinner(int index) async {
    if (_matchWinnerIndex != null) return;
    setState(() {
      _editMode = false;
      _setMatchWinnerState(index);
    });
    await _recordMatchResult(index);
  }

  Future<void> _showMatchInfoModal({
    required String title,
    String? subtitle,
    required String message,
    String buttonText = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.10),
            child: Container(
              width: 560,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.34),
                    Colors.white.withValues(alpha: 0.14),
                    Colors.white.withValues(alpha: 0.26),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 22,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: Container(
                  color: const Color(0xFF05080D),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: GridPainter(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.skewX(0.10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              if (subtitle != null &&
                                  subtitle.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Text(
                                message,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withValues(alpha: 0.84),
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 26),
                              Center(
                                child: BakuganButton(
                                  text: buttonText,
                                  onPressed: () => Navigator.of(context).pop(),
                                  width: 180,
                                  height: 78,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUsedGateRemovalReminder() {
    return _showMatchInfoModal(
      title: 'REMOVE GATE EFFECT',
      subtitle: 'MATCH REMINDER',
      message:
          'If the gate card removed had an effect, remove it by holding the card.',
    );
  }

  int _scoreIndexForPlayer(PlayerData player) {
    final playerIndex = widget.players.indexOf(player);
    if (playerIndex < 0) return 0;
    if (!widget.isTeamBattle) return playerIndex;
    return playerIndex.isEven ? 0 : 1;
  }

  Future<void> _recordLeaderboardMatch(int winningScoreIndex) async {
    final gateCardsWonByPlayer = <String, int>{};
    for (final player in widget.players) {
      if (!player.isSavedProfile) continue;
      gateCardsWonByPlayer[player.name] = scores[_scoreIndexForPlayer(player)];
    }

    if (widget.isTeamBattle) {
      final winners = winningScoreIndex == 0
          ? [widget.players[0], widget.players[2]]
          : [widget.players[1], widget.players[3]];
      final losers = winningScoreIndex == 0
          ? [widget.players[1], widget.players[3]]
          : [widget.players[0], widget.players[2]];
      await LeaderboardRepository.instance.recordMatch(
        winners: winners
            .where((player) => player.isSavedProfile)
            .map((player) => player.name)
            .toList(),
        losers: losers
            .where((player) => player.isSavedProfile)
            .map((player) => player.name)
            .toList(),
        gateCardsWonByPlayer: gateCardsWonByPlayer,
      );
      return;
    }

    final winner = widget.players[winningScoreIndex];
    final losers = [
      for (int i = 0; i < widget.players.length; i++)
        if (i != winningScoreIndex) widget.players[i],
    ];
    await LeaderboardRepository.instance.recordMatch(
      winners: winner.isSavedProfile ? [winner.name] : const [],
      losers: losers
          .where((player) => player.isSavedProfile)
          .map((player) => player.name)
          .toList(),
      gateCardsWonByPlayer: gateCardsWonByPlayer,
    );
  }

  int _totalEloMatches(LeaderboardStore store) => store
      .currentLeaderboard
      .players
      .fold<int>(0, (sum, player) => sum + player.matches);

  Future<void> _recordMatchHistory(
    int winningScoreIndex, {
    bool countedForElo = true,
  }) async {
    final winnerNames = widget.isTeamBattle
        ? (winningScoreIndex == 0
              ? [widget.players[0].name, widget.players[2].name]
              : [widget.players[1].name, widget.players[3].name])
        : [widget.players[winningScoreIndex].name];

    final historyPlayers = <MatchHistoryPlayerEntry>[
      for (int i = 0; i < widget.players.length; i++)
        MatchHistoryPlayerEntry(
          name: widget.players[i].name,
          character: widget.players[i].character,
          isSavedProfile: widget.players[i].isSavedProfile,
          isWinner: winnerNames.any(
            (winner) =>
                _playerNameKey(winner) ==
                _playerNameKey(widget.players[i].name),
          ),
          gateCardsWon: scores[_scoreIndexForPlayer(widget.players[i])],
          bakuganUsed: widget.players[i].deck
              .map(
                (variant) => MatchHistoryBakuganEntry(
                  speciesName: variant.speciesName,
                  attribute: variant.attribute,
                  gPower: variant.gPower,
                  modelPath: variant.modelPath,
                  texturePath: variant.texturePath,
                  imagePath: _historyBakuganImagePath(
                    speciesName: variant.speciesName,
                    attribute: variant.attribute,
                  ),
                ),
              )
              .toList(),
          abilitiesUsed:
              (_abilitiesUsedByPlayer[widget.players[i].name] ??
                      const <String>{})
                  .toList()
                ..sort(),
          abilitySlots: List<MatchHistoryAbilitySlotEntry>.generate(3, (
            slotIndex,
          ) {
            final presented = _presentedMatchAbilities[i][slotIndex];
            return MatchHistoryAbilitySlotEntry(
              slotIndex: slotIndex,
              card: presented == null
                  ? null
                  : MatchHistoryCardEntry(
                      name: presented.card.name,
                      imagePath: presented.card.imagePath,
                    ),
            );
          }),
        ),
    ];

    final now = DateTime.now();
    final entry = MatchHistoryEntry(
      id: now.microsecondsSinceEpoch.toString(),
      seasonNumber: (await LeaderboardRepository.instance.loadStore())
          .currentSeasonNumber,
      isTeamBattle: widget.isTeamBattle,
      playedAt: now.toIso8601String(),
      winnerNames: winnerNames.map(_sanitizePlayerName).toList(),
      players: historyPlayers,
      battles: List<MatchBattleRecord>.from(_battleHistory),
      countedForElo: countedForElo,
    );
    await LeaderboardRepository.instance.recordMatchHistory(entry);
  }

  MatchHistoryCardEntry _historyCardEntryForAbilityName(String name) {
    final normalized = name.trim().toLowerCase();
    for (final card in _matchAbilityCards.values) {
      if (card.name.trim().toLowerCase() == normalized) {
        return MatchHistoryCardEntry(
          name: card.name,
          imagePath: card.imagePath,
        );
      }
    }
    return MatchHistoryCardEntry(
      name: name,
      imagePath: 'assets/images/cards/anverse.png',
    );
  }

  void _playClick() async {
    await _sfxPlayer.stop();
    await _sfxPlayer.play(AssetSource('sound/select_2.wav'));
  }

  Future<void> _playPointCaptureSound() async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource('sound/select.wav'));
    } catch (_) {}
  }

  Future<void> _playBakuganStaySound() async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource('sound/win_battle.mp3'));
    } catch (_) {}
  }

  Future<void> _playBakuganRemovedSound() async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.setReleaseMode(ReleaseMode.stop);
      await _sfxPlayer.play(AssetSource('sound/lose.mp3'));
    } catch (_) {}
  }

  Future<void> _showBakuganRemovedOverlay({
    required int playerIndex,
    required int bakuganIndex,
  }) async {
    if (_matchWinnerIndex != null) return;

    await _pauseArenaPlaylist();
    setState(() {
      _bakuganStayBannerText = 'REMOVED';
      _bakuganStayPlayerIndex = playerIndex;
      _bakuganStayBakuganIndex = bakuganIndex;
      _bakuganStayClosing = false;
    });

    final soundFinished = Future.any<void>([
      _sfxPlayer.onPlayerComplete.first.then((_) {}),
      Future<void>.delayed(const Duration(seconds: 4)),
    ]);
    await _playBakuganRemovedSound();
    if (!mounted) return;

    await soundFinished;
    if (!mounted) return;

    await _hideBakuganResultOverlay();
    await _resumeArenaPlaylist();
  }

  void _clearBattleSelectionForSlot(int playerIndex, int bakuganIndex) {
    final player = widget.players[playerIndex];
    if (leftPlayer == player && leftBakuganIdx == bakuganIndex) {
      leftPlayer = null;
      leftBakugan = null;
      leftBakuganIdx = null;
    }
    if (rightPlayer == player && rightBakuganIdx == bakuganIndex) {
      rightPlayer = null;
      rightBakugan = null;
      rightBakuganIdx = null;
    }
  }

  void _refreshUnusedPileIfNeeded(int playerIndex) {
    final deckLength = widget.players[playerIndex].deck.length;
    final states = _bakuganPileStates[playerIndex];
    final hasUnused = List.generate(
      deckLength,
      (index) => states[index],
    ).any((state) => state == MatchBakuganPileState.unused);
    final usedIndices = List.generate(
      deckLength,
      (index) => index,
    ).where((index) => states[index] == MatchBakuganPileState.used);

    if (hasUnused || usedIndices.isEmpty) return;

    for (final index in usedIndices) {
      states[index] = MatchBakuganPileState.unused;
      _bakuganStandOrder[playerIndex][index] = null;
    }
  }

  bool _canUseBakuganStay(int playerIndex) {
    final deckLength = widget.players[playerIndex].deck.length;
    if (deckLength < 3) return false;
    return List.generate(
      3,
      (index) => _bakuganPileStates[playerIndex][index],
    ).every((state) => state == MatchBakuganPileState.standing);
  }

  int? _oldestStandingBakuganIndex(int playerIndex) {
    int? oldestIndex;
    int? oldestOrder;
    for (int i = 0; i < min(3, widget.players[playerIndex].deck.length); i++) {
      if (_bakuganPileStates[playerIndex][i] !=
          MatchBakuganPileState.standing) {
        continue;
      }
      final order = _bakuganStandOrder[playerIndex][i];
      if (order == null) continue;
      if (oldestOrder == null || order < oldestOrder) {
        oldestOrder = order;
        oldestIndex = i;
      }
    }
    return oldestIndex;
  }

  void _handleBakuganTap(
    PlayerData player,
    int playerIndex,
    int bakuganIndex,
    bool isMirrored,
  ) {
    if (bakuganIndex >= player.deck.length) return;
    // In edit mode a Bakugan is only doomed or not (corner button).
    if (_editMode) return;
    final currentState = _bakuganPileStates[playerIndex][bakuganIndex];
    if (selectionMode) {
      if (currentState != MatchBakuganPileState.standing) return;

      _playClick();
      setState(() {
        final isLeftSelected =
            leftPlayer == player && leftBakuganIdx == bakuganIndex;
        final isRightSelected =
            rightPlayer == player && rightBakuganIdx == bakuganIndex;

        if (isLeftSelected) {
          leftPlayer = null;
          leftBakugan = null;
          leftBakuganIdx = null;
          return;
        }
        if (isRightSelected) {
          rightPlayer = null;
          rightBakugan = null;
          rightBakuganIdx = null;
          return;
        }

        if (leftPlayer == null) {
          leftPlayer = player;
          leftBakugan = player.deck[bakuganIndex];
          leftBakuganIdx = bakuganIndex;
          return;
        }
        if (rightPlayer == null) {
          rightPlayer = player;
          rightBakugan = player.deck[bakuganIndex];
          rightBakuganIdx = bakuganIndex;
          return;
        }

        leftPlayer = player;
        leftBakugan = player.deck[bakuganIndex];
        leftBakuganIdx = bakuganIndex;
      });
      return;
    }

    if (currentState == MatchBakuganPileState.removed) return;

    // Pile -> in play -> used -> pile. "Out" is only set from the edit mode.
    final next = switch (currentState) {
      MatchBakuganPileState.unused => MatchBakuganPileState.standing,
      MatchBakuganPileState.standing => MatchBakuganPileState.used,
      _ => MatchBakuganPileState.unused,
    };
    _playClick();
    setState(() {
      _bakuganPileStates[playerIndex][bakuganIndex] = next;
      _bakuganStandOrder[playerIndex][bakuganIndex] =
          next == MatchBakuganPileState.standing ? _nextStandOrder++ : null;
      _clearBattleSelectionForSlot(playerIndex, bakuganIndex);
      _refreshUnusedPileIfNeeded(playerIndex);
    });
  }

  Future<void> _triggerBakuganStay(int playerIndex) async {
    if (_isResolvingBakuganStay || _matchWinnerIndex != null) return;
    final oldestStandingIndex = _oldestStandingBakuganIndex(playerIndex);
    if (oldestStandingIndex == null) return;

    _isResolvingBakuganStay = true;
    setState(() {
      _bakuganStayBannerText = 'STAY!';
      _bakuganStayPlayerIndex = playerIndex;
      _bakuganStayBakuganIndex = oldestStandingIndex;
      _bakuganStayClosing = false;
    });

    final soundFinished = Future.any<void>([
      _sfxPlayer.onPlayerComplete.first.then((_) {}),
      Future<void>.delayed(const Duration(seconds: 4)),
    ]);
    await _playBakuganStaySound();
    if (!mounted) return;

    await soundFinished;
    if (!mounted) return;

    setState(() {
      _bakuganPileStates[playerIndex][oldestStandingIndex] =
          MatchBakuganPileState.unused;
      _bakuganStandOrder[playerIndex][oldestStandingIndex] = null;
      _clearBattleSelectionForSlot(playerIndex, oldestStandingIndex);
    });
    _addPoint(
      _scoreIndexForPlayer(widget.players[playerIndex]),
      playPointSound: false,
    );

    await _hideBakuganResultOverlay();
    _isResolvingBakuganStay = false;
  }

  void _markBattlingBakuganUsedAndClearSelection({
    required int leftBakuganIndex,
    required int rightBakuganIndex,
    int? removedBakuganSideIndex,
  }) {
    final leftPlayerLocal = leftPlayer;
    final rightPlayerLocal = rightPlayer;
    final leftIdxLocal = leftBakuganIdx;
    final rightIdxLocal = rightBakuganIdx;

    setState(() {
      if (leftPlayerLocal != null && leftIdxLocal != null) {
        final playerIndex = widget.players.indexOf(leftPlayerLocal);
        if (playerIndex >= 0 &&
            leftIdxLocal < _bakuganPileStates[playerIndex].length) {
          _bakuganPileStates[playerIndex][leftIdxLocal] =
              MatchBakuganPileState.used;
          _bakuganStandOrder[playerIndex][leftIdxLocal] = null;
          _refreshUnusedPileIfNeeded(playerIndex);
        }
      }
      if (leftPlayerLocal != null) {
        final playerIndex = widget.players.indexOf(leftPlayerLocal);
        if (playerIndex >= 0 &&
            leftBakuganIndex < _bakuganPileStates[playerIndex].length) {
          _bakuganPileStates[playerIndex][leftBakuganIndex] =
              removedBakuganSideIndex == 0
              ? MatchBakuganPileState.removed
              : MatchBakuganPileState.used;
          _bakuganStandOrder[playerIndex][leftBakuganIndex] = null;
          _refreshUnusedPileIfNeeded(playerIndex);
        }
      }

      if (rightPlayerLocal != null && rightIdxLocal != null) {
        final playerIndex = widget.players.indexOf(rightPlayerLocal);
        if (playerIndex >= 0 &&
            rightIdxLocal < _bakuganPileStates[playerIndex].length) {
          _bakuganPileStates[playerIndex][rightIdxLocal] =
              MatchBakuganPileState.used;
          _bakuganStandOrder[playerIndex][rightIdxLocal] = null;
          _refreshUnusedPileIfNeeded(playerIndex);
        }
      }
      if (rightPlayerLocal != null) {
        final playerIndex = widget.players.indexOf(rightPlayerLocal);
        if (playerIndex >= 0 &&
            rightBakuganIndex < _bakuganPileStates[playerIndex].length) {
          _bakuganPileStates[playerIndex][rightBakuganIndex] =
              removedBakuganSideIndex == 1
              ? MatchBakuganPileState.removed
              : MatchBakuganPileState.used;
          _bakuganStandOrder[playerIndex][rightBakuganIndex] = null;
          _refreshUnusedPileIfNeeded(playerIndex);
        }
      }

      selectionMode = false;
      leftBakugan = null;
      rightBakugan = null;
      leftPlayer = null;
      rightPlayer = null;
      leftBakuganIdx = null;
      rightBakuganIdx = null;
    });
  }

  @override
  void dispose() {
    _currentHelpTopic.removeListener(_claimPauseButtonIfOnTop);
    AutomationController.instance.removeListener(_onAutomationChanged);
    // A newer scoreboard (after Restart) may already own the pause button by
    // the time this one is disposed, so only release what is still ours.
    if (identical(_matchPauseController.value, _matchPauseMenuController)) {
      _matchPauseController.value = null;
      _scoreboardOwnsPauseButton.value = false;
    }
    _matchCardNameController.dispose();
    _matchCardNameFocusNode.dispose();
    AppVolumeController.instance.unregister(_arenaPlayerA);
    AppVolumeController.instance.unregister(_arenaPlayerB);
    AppVolumeController.instance.unregister(_sfxPlayer);
    _arenaPlayerA.dispose();
    _arenaPlayerB.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }

  // Between screens the pause button state can be left by another (older)
  // scoreboard; whichever one is on top takes it back.
  void _onAutomationChanged() {
    if (mounted) setState(() {});
  }

  // --- Manual edit of the match (manual / assisted) -------------------------
  // The pencil button turns the match screen into an edit mode: the players
  // expand like when choosing a battle, every Bakugan gets a corner button to
  // send it out of the game (or bring it back), and the points get "+" / "-".

  bool _editMode = false;

  void _setEditMode(bool value) {
    setState(() {
      _editMode = value;
      if (value) {
        selectionMode = false;
        leftBakugan = null;
        rightBakugan = null;
        leftPlayer = null;
        rightPlayer = null;
        leftBakuganIdx = null;
        rightBakuganIdx = null;
      }
    });
  }

  void _setBakuganOut(int playerIndex, int bakuganIndex, bool isOut) {
    _playClick();
    setState(() {
      _bakuganPileStates[playerIndex][bakuganIndex] = isOut
          ? MatchBakuganPileState.removed
          : MatchBakuganPileState.unused;
      _bakuganStandOrder[playerIndex][bakuganIndex] = null;
      _clearBattleSelectionForSlot(playerIndex, bakuganIndex);
    });
  }

  void _adjustScoreByHand(int scoreIndex, int delta) {
    if (delta > 0) {
      if (scores[scoreIndex] < 3) _addPoint(scoreIndex);
      return;
    }
    if (scores[scoreIndex] <= 0 || _matchWinnerIndex != null) return;
    _playClick();
    setState(() => scores[scoreIndex]--);
  }

  void _claimPauseButtonIfOnTop() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    _matchPauseController.value = _matchPauseMenuController;
    _scoreboardOwnsPauseButton.value = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only the screen on top owns the pause menu (the arena takes it over
    // while it is open).
    if (ModalRoute.of(context)?.isCurrent == true &&
        !identical(_matchPauseController.value, _matchPauseMenuController)) {
      _matchPauseController.value = _matchPauseMenuController;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMatchWinner = _matchWinnerIndex != null;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape):
            const ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (_) {
              _openAppSettingsDialog();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/match-bg.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  _buildArenaPlaylistBar(),
                  IgnorePointer(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 600,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  blurRadius: 100,
                                  spreadRadius: 120,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildGlobalGateEffectRail(),

                  if (!widget.isTeamBattle) ...[
                    _buildCornerPlayer(0, Alignment.topLeft),
                    _buildCornerPlayer(1, Alignment.topRight),
                    if (widget.players.length > 2)
                      _buildCornerPlayer(2, Alignment.bottomLeft),
                    if (widget.players.length > 3)
                      _buildCornerPlayer(3, Alignment.bottomRight),
                  ] else ...[
                    // Team 1 (Left Staircase)
                    _buildTeamStaircase(0, 2, false),
                    // Team 2 (Right Staircase)
                    _buildTeamStaircase(1, 3, true),
                  ],

                  // Battle button
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_editMode)
                            FramedActionButton(
                              text: 'DONE',
                              gradient: _solidFrame(const Color(0xFF3FD0DC)),
                              onPressed: () => _setEditMode(false),
                              width: 300,
                              height: 85,
                            )
                          else ...[
                            if (selectionMode) ...[
                              FramedActionButton(
                                text: 'BACK',
                                onPressed: () {
                                  setState(() {
                                    selectionMode = false;
                                    leftBakugan = null;
                                    rightBakugan = null;
                                    leftPlayer = null;
                                    rightPlayer = null;
                                    leftBakuganIdx = null;
                                    rightBakuganIdx = null;
                                  });
                                },
                                useCancelSound: true,
                                width: 180,
                                height: 85,
                                gradient: _solidFrame(const Color(0xFFB8C2CC)),
                                accentColor: const Color(0xFFE8EDF2),
                              ),
                              const SizedBox(width: 14),
                            ],
                            FramedActionButton(
                              text: !selectionMode
                                  ? 'BATTLE'
                                  : (leftBakugan != null && rightBakugan != null
                                        ? 'FIGHT!'
                                        : 'CHOOSE...'),
                              onPressed: () {
                                if (!selectionMode) {
                                  setState(() {
                                    selectionMode = true;
                                    leftBakugan = null;
                                    rightBakugan = null;
                                    leftPlayer = null;
                                    rightPlayer = null;
                                  });
                                } else if (leftBakugan != null &&
                                    rightBakugan != null) {
                                  final leftPlayerIndex = widget.players
                                      .indexOf(leftPlayer!);
                                  final rightPlayerIndex = widget.players
                                      .indexOf(rightPlayer!);
                                  final leftScoreIndex = _scoreIndexForPlayer(
                                    leftPlayer!,
                                  );
                                  final rightScoreIndex = _scoreIndexForPlayer(
                                    rightPlayer!,
                                  );
                                  final leftUnusedBakuganIndices =
                                      List.generate(
                                            _bakuganPileStates[leftPlayerIndex]
                                                .length,
                                            (index) => index,
                                          )
                                          .where(
                                            (index) =>
                                                _bakuganPileStates[leftPlayerIndex][index] ==
                                                    MatchBakuganPileState
                                                        .unused &&
                                                index != leftBakuganIdx,
                                          )
                                          .toList();
                                  final rightUnusedBakuganIndices =
                                      List.generate(
                                            _bakuganPileStates[rightPlayerIndex]
                                                .length,
                                            (index) => index,
                                          )
                                          .where(
                                            (index) =>
                                                _bakuganPileStates[rightPlayerIndex][index] ==
                                                    MatchBakuganPileState
                                                        .unused &&
                                                index != rightBakuganIdx,
                                          )
                                          .toList();
                                  final leftUsedBakuganIndices =
                                      List.generate(
                                            _bakuganPileStates[leftPlayerIndex]
                                                .length,
                                            (index) => index,
                                          )
                                          .where(
                                            (index) =>
                                                _bakuganPileStates[leftPlayerIndex][index] ==
                                                    MatchBakuganPileState
                                                        .used &&
                                                index != leftBakuganIdx,
                                          )
                                          .toList();
                                  final rightUsedBakuganIndices =
                                      List.generate(
                                            _bakuganPileStates[rightPlayerIndex]
                                                .length,
                                            (index) => index,
                                          )
                                          .where(
                                            (index) =>
                                                _bakuganPileStates[rightPlayerIndex][index] ==
                                                    MatchBakuganPileState
                                                        .used &&
                                                index != rightBakuganIdx,
                                          )
                                          .toList();
                                  final usedBakuganIndicesByPlayer = {
                                    for (
                                      int playerIndex = 0;
                                      playerIndex < _bakuganPileStates.length;
                                      playerIndex++
                                    )
                                      playerIndex:
                                          List.generate(
                                                _bakuganPileStates[playerIndex]
                                                    .length,
                                                (index) => index,
                                              )
                                              .where(
                                                (index) =>
                                                    _bakuganPileStates[playerIndex][index] ==
                                                    MatchBakuganPileState.used,
                                              )
                                              .toList(),
                                  };

                                  _pauseArenaPlaylist();
                                  _scoreboardOwnsPauseButton.value = false;
                                  Navigator.push(
                                    context,
                                    _fadeRoute(
                                      BattleArenaScreen(
                                        leftPlayer: leftPlayer!,
                                        rightPlayer: rightPlayer!,
                                        matchPlayers: widget.players,
                                        leftPlayerIndex: leftPlayerIndex,
                                        rightPlayerIndex: rightPlayerIndex,
                                        leftBakuganDeckIndex: leftBakuganIdx!,
                                        rightBakuganDeckIndex: rightBakuganIdx!,
                                        leftBakugan: leftBakugan!,
                                        rightBakugan: rightBakugan!,
                                        leftUnusedBakuganIndices:
                                            leftUnusedBakuganIndices,
                                        rightUnusedBakuganIndices:
                                            rightUnusedBakuganIndices,
                                        leftUsedBakuganIndices:
                                            leftUsedBakuganIndices,
                                        rightUsedBakuganIndices:
                                            rightUsedBakuganIndices,
                                        usedBakuganIndicesByPlayer:
                                            usedBakuganIndicesByPlayer,
                                        usedGateCardsInAllPiles: scores.fold(
                                          0,
                                          (sum, score) => sum + score,
                                        ),
                                        leftUsedGateCards:
                                            scores[leftScoreIndex],
                                        rightUsedGateCards:
                                            scores[rightScoreIndex],
                                        presentedMatchAbilities:
                                            _presentedMatchAbilities,
                                        activeGlobalGateCards:
                                            _activeGlobalGateEffects,
                                      ),
                                    ),
                                  ).then((result) async {
                                    if (!mounted) return;
                                    _scoreboardOwnsPauseButton.value = true;
                                    final resultMap = result is Map
                                        ? Map<String, dynamic>.from(result)
                                        : const <String, dynamic>{};
                                    final int? winnerIndex =
                                        resultMap['winnerIndex'] as int?;
                                    final bool isTieResult =
                                        resultMap['isTieResult'] == true;
                                    final int? usedGatePenaltySideIndex =
                                        resultMap['usedGatePenaltySideIndex']
                                            as int?;
                                    final int? removedBakuganSideIndex =
                                        resultMap['removedBakuganSideIndex']
                                            as int?;
                                    final GateCard? revealedGateCard =
                                        resultMap['revealedGateCard']
                                            is GateCard
                                        ? resultMap['revealedGateCard']
                                              as GateCard
                                        : null;
                                    final int leftReturnedBakuganIndex =
                                        resultMap['leftBakuganIndex'] is int
                                        ? resultMap['leftBakuganIndex'] as int
                                        : leftBakuganIdx!;
                                    final int rightReturnedBakuganIndex =
                                        resultMap['rightBakuganIndex'] is int
                                        ? resultMap['rightBakuganIndex'] as int
                                        : rightBakuganIdx!;
                                    final previousLeftPlayer = leftPlayer;
                                    final previousRightPlayer = rightPlayer;
                                    final leftAbilitiesUsed =
                                        resultMap['leftAbilitiesUsed'] is List
                                        ? (resultMap['leftAbilitiesUsed']
                                                  as List)
                                              .map((entry) => entry.toString())
                                              .where(
                                                (entry) =>
                                                    entry.trim().isNotEmpty,
                                              )
                                              .toList()
                                        : const <String>[];
                                    final rightAbilitiesUsed =
                                        resultMap['rightAbilitiesUsed'] is List
                                        ? (resultMap['rightAbilitiesUsed']
                                                  as List)
                                              .map((entry) => entry.toString())
                                              .where(
                                                (entry) =>
                                                    entry.trim().isNotEmpty,
                                              )
                                              .toList()
                                        : const <String>[];
                                    final externalAbilitiesUsed =
                                        resultMap['externalAbilitiesUsed']
                                            is List
                                        ? (resultMap['externalAbilitiesUsed']
                                                  as List)
                                              .map((entry) {
                                                if (entry
                                                    is MatchHistoryCardEntry) {
                                                  return entry;
                                                }
                                                if (entry is Map) {
                                                  return MatchHistoryCardEntry.fromJson(
                                                    Map<String, dynamic>.from(
                                                      entry,
                                                    ),
                                                  );
                                                }
                                                return MatchHistoryCardEntry(
                                                  name: entry.toString(),
                                                  imagePath:
                                                      'assets/images/cards/anverse.png',
                                                );
                                              })
                                              .where(
                                                (entry) => entry.name
                                                    .trim()
                                                    .isNotEmpty,
                                              )
                                              .toList()
                                        : const <MatchHistoryCardEntry>[];
                                    final leftFinalGPower =
                                        (resultMap['leftFinalGPower'] as num?)
                                            ?.toInt() ??
                                        (leftBakugan?.gPower ?? 0);
                                    final rightFinalGPower =
                                        (resultMap['rightFinalGPower'] as num?)
                                            ?.toInt() ??
                                        (rightBakugan?.gPower ?? 0);
                                    final PlayerData? winningPlayer =
                                        winnerIndex == null
                                        ? null
                                        : winnerIndex == 0
                                        ? previousLeftPlayer
                                        : previousRightPlayer;
                                    final leftBakuganSpecies =
                                        leftBakugan?.speciesName ?? '';
                                    final leftBakuganAttribute =
                                        leftBakugan?.attribute ?? '';
                                    final rightBakuganSpecies =
                                        rightBakugan?.speciesName ?? '';
                                    final rightBakuganAttribute =
                                        rightBakugan?.attribute ?? '';
                                    final hasRemovedBakugan =
                                        removedBakuganSideIndex != null;
                                    if (winnerIndex != null || isTieResult) {
                                      _battleHistory.add(
                                        MatchBattleRecord(
                                          battleNumber:
                                              _battleHistory.length + 1,
                                          leftPlayerName:
                                              previousLeftPlayer?.name ?? '',
                                          rightPlayerName:
                                              previousRightPlayer?.name ?? '',
                                          leftSide: MatchHistoryBattleSideEntry(
                                            bakugan: MatchHistoryBakuganEntry(
                                              speciesName: leftBakuganSpecies,
                                              attribute: leftBakuganAttribute,
                                              gPower: leftBakugan?.gPower ?? 0,
                                              modelPath:
                                                  leftBakugan?.modelPath ?? '',
                                              texturePath:
                                                  leftBakugan?.texturePath,
                                              imagePath:
                                                  leftBakuganSpecies.isEmpty ||
                                                      leftBakuganAttribute
                                                          .isEmpty
                                                  ? ''
                                                  : _historyBakuganImagePath(
                                                      speciesName:
                                                          leftBakuganSpecies,
                                                      attribute:
                                                          leftBakuganAttribute,
                                                    ),
                                            ),
                                            finalGPower: leftFinalGPower,
                                            isWinner: winnerIndex == 0,
                                            abilitiesUsed: leftAbilitiesUsed
                                                .map(
                                                  _historyCardEntryForAbilityName,
                                                )
                                                .toList(),
                                          ),
                                          rightSide: MatchHistoryBattleSideEntry(
                                            bakugan: MatchHistoryBakuganEntry(
                                              speciesName: rightBakuganSpecies,
                                              attribute: rightBakuganAttribute,
                                              gPower: rightBakugan?.gPower ?? 0,
                                              modelPath:
                                                  rightBakugan?.modelPath ?? '',
                                              texturePath:
                                                  rightBakugan?.texturePath,
                                              imagePath:
                                                  rightBakuganSpecies.isEmpty ||
                                                      rightBakuganAttribute
                                                          .isEmpty
                                                  ? ''
                                                  : _historyBakuganImagePath(
                                                      speciesName:
                                                          rightBakuganSpecies,
                                                      attribute:
                                                          rightBakuganAttribute,
                                                    ),
                                            ),
                                            finalGPower: rightFinalGPower,
                                            isWinner: winnerIndex == 1,
                                            abilitiesUsed: rightAbilitiesUsed
                                                .map(
                                                  _historyCardEntryForAbilityName,
                                                )
                                                .toList(),
                                          ),
                                          winnerName: winningPlayer?.name,
                                          revealedGateCard:
                                              revealedGateCard == null
                                              ? null
                                              : MatchHistoryCardEntry(
                                                  name: revealedGateCard.name,
                                                  imagePath: revealedGateCard
                                                      .imagePath,
                                                ),
                                          externalAbilitiesUsed:
                                              externalAbilitiesUsed,
                                        ),
                                      );
                                    }
                                    for (final ability in leftAbilitiesUsed) {
                                      _abilitiesUsedByPlayer
                                          .putIfAbsent(
                                            previousLeftPlayer?.name ?? '',
                                            () => <String>{},
                                          )
                                          .add(ability);
                                    }
                                    for (final ability in rightAbilitiesUsed) {
                                      _abilitiesUsedByPlayer
                                          .putIfAbsent(
                                            previousRightPlayer?.name ?? '',
                                            () => <String>{},
                                          )
                                          .add(ability);
                                    }
                                    if (!hasRemovedBakugan) {
                                      unawaited(_resumeArenaPlaylist());
                                    }
                                    _markBattlingBakuganUsedAndClearSelection(
                                      leftBakuganIndex:
                                          leftReturnedBakuganIndex,
                                      rightBakuganIndex:
                                          rightReturnedBakuganIndex,
                                      removedBakuganSideIndex:
                                          removedBakuganSideIndex,
                                    );
                                    final awardedScoreIndex =
                                        winningPlayer == null
                                        ? null
                                        : _scoreIndexForPlayer(winningPlayer);
                                    final penalizedPlayer =
                                        usedGatePenaltySideIndex == null
                                        ? null
                                        : usedGatePenaltySideIndex == 0
                                        ? previousLeftPlayer
                                        : previousRightPlayer;
                                    final penalizedScoreIndex =
                                        penalizedPlayer == null
                                        ? null
                                        : _scoreIndexForPlayer(penalizedPlayer);
                                    bool didWinMatch = false;
                                    if (awardedScoreIndex != null ||
                                        penalizedScoreIndex != null) {
                                      setState(() {
                                        if (awardedScoreIndex != null &&
                                            awardedScoreIndex >= 0 &&
                                            awardedScoreIndex < scores.length &&
                                            scores[awardedScoreIndex] < 3) {
                                          scores[awardedScoreIndex]++;
                                        }
                                        if (penalizedScoreIndex != null &&
                                            penalizedScoreIndex >= 0 &&
                                            penalizedScoreIndex <
                                                scores.length &&
                                            scores[penalizedScoreIndex] > 0) {
                                          scores[penalizedScoreIndex]--;
                                        }

                                        final resolvedWinnerIndex = scores
                                            .indexWhere((score) => score >= 3);
                                        if (resolvedWinnerIndex >= 0 &&
                                            _declaresMatchWinnerAutomatically) {
                                          didWinMatch = true;
                                          _setMatchWinnerState(
                                            resolvedWinnerIndex,
                                          );
                                        } else {
                                          _matchWinnerIndex = null;
                                        }

                                        if (AutomationController
                                                    .instance
                                                    .level !=
                                                AutomationLevel.manual &&
                                            winningPlayer != null &&
                                            (revealedGateCard
                                                    ?.hasUsedPileGlobalAttributeBonus ??
                                                false) &&
                                            !_activeGlobalGateEffects.any(
                                              (active) =>
                                                  active.key ==
                                                  revealedGateCard!.key,
                                            )) {
                                          _activeGlobalGateEffects.add(
                                            revealedGateCard!,
                                          );
                                        }
                                      });
                                      if (awardedScoreIndex != null) {
                                        unawaited(_playPointCaptureSound());
                                      }
                                      if (didWinMatch) {
                                        await _recordMatchResult(
                                          _matchWinnerIndex!,
                                          awaitSound: false,
                                        );
                                      }
                                    }
                                    if (removedBakuganSideIndex != null) {
                                      final removedPlayer =
                                          removedBakuganSideIndex == 0
                                          ? previousLeftPlayer
                                          : previousRightPlayer;
                                      final removedBakuganIndex =
                                          removedBakuganSideIndex == 0
                                          ? leftReturnedBakuganIndex
                                          : rightReturnedBakuganIndex;
                                      if (removedPlayer != null) {
                                        final removedPlayerIndex = widget
                                            .players
                                            .indexOf(removedPlayer);
                                        if (removedPlayerIndex >= 0) {
                                          unawaited(
                                            _showBakuganRemovedOverlay(
                                              playerIndex: removedPlayerIndex,
                                              bakuganIndex: removedBakuganIndex,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                    if (usedGatePenaltySideIndex != null) {
                                      if (penalizedPlayer != null) {
                                        unawaited(
                                          _showUsedGateRemovalReminder(),
                                        );
                                      }
                                    }
                                  });
                                }
                              },
                              gradient:
                                  (selectionMode &&
                                      (leftBakugan == null ||
                                          rightBakugan == null))
                                  ? _solidFrame(const Color(0xFF78909C))
                                  : _solidFrame(const Color(0xFF3FD0DC)),
                              accentColor:
                                  (selectionMode &&
                                      (leftBakugan == null ||
                                          rightBakugan == null))
                                  ? Colors.blueGrey
                                  : Colors.cyanAccent,
                              width: 300,
                              height: 85,
                            ),
                            if (!selectionMode) ...[
                              const SizedBox(width: 14),
                              FramedActionButton(
                                icon: Icons.pause_rounded,
                                gradient: _solidFrame(const Color(0xFF3FD0DC)),
                                onPressed: _openAppSettingsDialog,
                                width: 85,
                                height: 85,
                              ),
                              // Manual edit of piles and points (not in auto).
                              if (AutomationController
                                  .instance
                                  .level
                                  .showsManualTools) ...[
                                const SizedBox(width: 14),
                                FramedActionButton(
                                  icon: Icons.edit_rounded,
                                  gradient: _solidFrame(
                                    const Color(0xFF3FD0DC),
                                  ),
                                  onPressed: () => _setEditMode(true),
                                  width: 85,
                                  height: 85,
                                ),
                              ],
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),

                  _buildMatchAbilityOverlay(),
                  _buildBakuganStayOverlay(),
                  _buildGameStartOverlay(),
                  if (hasMatchWinner) _buildMatchWinnerOverlay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameStartOverlay() {
    if (!_showGameStartBanner) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOutCubic,
                opacity: _showGameStartBannerContent ? 1 : 0,
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
            ),
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                opacity: _showGameStartBannerContent ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeInOutCubic,
                  offset: _gameStartBannerOffset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.9),
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.lightBlueAccent.withValues(alpha: 0.32),
                          blurRadius: 28,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: Colors.cyanAccent.withValues(alpha: 0.18),
                          blurRadius: 44,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      'GAME START',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'title_font',
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 2.4,
                        color: const Color(0xFF8BEBFF),
                        shadows: [
                          Shadow(
                            color: Colors.white.withValues(alpha: 0.95),
                            blurRadius: 10,
                          ),
                          Shadow(
                            color: Colors.lightBlueAccent.withValues(
                              alpha: 0.95,
                            ),
                            blurRadius: 24,
                          ),
                          Shadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.8),
                            blurRadius: 42,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamStaircase(int p1Idx, int p2Idx, bool isMirrored) {
    return Positioned(
      top: 40,
      left: isMirrored ? null : 40,
      right: isMirrored ? 40 : null,
      child: Column(
        crossAxisAlignment: isMirrored
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Player 1
          _buildPlayerForTeam(p1Idx, isMirrored),
          const SizedBox(height: 25),
          // Player 2 (Offset for staircase)
          Padding(
            padding: EdgeInsets.only(
              left: isMirrored ? 0 : 70,
              right: isMirrored ? 70 : 0,
            ),
            child: _buildPlayerForTeam(p2Idx, isMirrored),
          ),
          const SizedBox(height: 40),
          // Team Score Ticks
          Padding(
            padding: EdgeInsets.only(
              left: isMirrored ? 0 : 130,
              right: isMirrored ? 130 : 0,
            ),
            child: _buildTicks(isMirrored ? 1 : 0),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerForTeam(int index, bool isMirrored) {
    final player = widget.players[index];
    bool isRed = (index == 1 || index == 3);
    final themeColor = isRed ? Colors.redAccent : Colors.blueAccent;

    return PlayerArenaInfo(
      player: player,
      isMirrored: isMirrored,
      themeColor: themeColor,
      isSelected: isRed,
      gradient: _playerGradient(index, isTeamBattle: true),
      glowAlpha: 0.6,
      thickness: 6.0,
      isSelecting: selectionMode,
      isExpanded: selectionMode || _editMode,
      selectedBakuganIndex: isMirrored
          ? (rightPlayer == player ? rightBakuganIdx : null)
          : (leftPlayer == player ? leftBakuganIdx : null),
      selectedBakuganIndices: {
        if (leftPlayer == player && leftBakuganIdx != null) leftBakuganIdx!,
        if (rightPlayer == player && rightBakuganIdx != null) rightBakuganIdx!,
      },
      onPortraitTap: null,
      portraitOverlay: _buildProfileAbilityOverlay(index, above: false),
      portraitOverlayAbove: false,
      trailingSlotBuilder: _stayTileBuilder(index),
      bakuganPileStates: _bakuganPileStates[index],
      isEditing: _editMode,
      onBakuganOut: (bIdx) => _setBakuganOut(index, bIdx, true),
      onBakuganBack: (bIdx) => _setBakuganOut(index, bIdx, false),
      onBakuganTap: (bIdx) =>
          _handleBakuganTap(player, index, bIdx, isMirrored),
    );
  }

  Widget _buildCornerPlayer(int index, Alignment alignment) {
    final player = widget.players[index];
    final bool isMirrored =
        alignment == Alignment.topRight || alignment == Alignment.bottomRight;
    bool isRed = index % 2 != 0;
    final themeColor = _playerThemeColor(index, isTeamBattle: false);

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(35.0),
        child: PlayerArenaInfo(
          player: player,
          isMirrored: isMirrored,
          themeColor: themeColor,
          extra: !widget.isTeamBattle ? _buildTicks(index) : null,
          isSelected: isRed,
          gradient: _playerGradient(index, isTeamBattle: false),
          glowAlpha: 0.6,
          thickness: 6.0,
          isSelecting: selectionMode,
          isExpanded: selectionMode || _editMode,
          selectedBakuganIndex: isMirrored
              ? (rightPlayer == player ? rightBakuganIdx : null)
              : (leftPlayer == player ? leftBakuganIdx : null),
          selectedBakuganIndices: {
            if (leftPlayer == player && leftBakuganIdx != null) leftBakuganIdx!,
            if (rightPlayer == player && rightBakuganIdx != null)
              rightBakuganIdx!,
          },
          onPortraitTap: null,
          portraitOverlay: _buildProfileAbilityOverlay(
            index,
            above:
                alignment == Alignment.bottomLeft ||
                alignment == Alignment.bottomRight,
          ),
          trailingSlotBuilder: _stayTileBuilder(index),
          portraitOverlayAbove:
              alignment == Alignment.bottomLeft ||
              alignment == Alignment.bottomRight,
          bakuganPileStates: _bakuganPileStates[index],
          isEditing: _editMode,
          onBakuganOut: (bIdx) => _setBakuganOut(index, bIdx, true),
          onBakuganBack: (bIdx) => _setBakuganOut(index, bIdx, false),
          onBakuganTap: (bIdx) =>
              _handleBakuganTap(player, index, bIdx, isMirrored),
        ),
      ),
    );
  }

  // Same skewed rectangle as the point bars, with a "+" or "-" inside.
  Widget _buildTickEditButton(int scoreIndex, int delta) {
    final color = delta > 0 ? Colors.greenAccent : Colors.redAccent;
    return GestureDetector(
      onTap: () => _adjustScoreByHand(scoreIndex, delta),
      behavior: HitTestBehavior.opaque,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.skewX(-0.25),
        // Filled like a scored point bar, in the colour of the action.
        child: Container(
          width: 35,
          height: 55,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.9),
                color.withValues(alpha: 0.4),
              ],
            ),
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(0.25),
            child: Icon(
              delta > 0 ? Icons.add : Icons.remove,
              color: Colors.white,
              size: delta > 0 ? 22 : 18,
            ),
          ),
        ),
      ),
    );
  }

  // Manual mode: gold tile, shaped like a point bar, that declares the winner.
  // It goes on the outer side of the score so the bars do not move.
  Widget _buildWinTick(int scoreIndex, {required bool mirrored}) {
    return _WinTick(
      mirrored: mirrored,
      onPressed: () => _declareMatchWinner(scoreIndex),
    );
  }

  Widget _buildTicks(int playerOrTeamIndex) {
    // With 3 points and no winner yet. In every mode; in auto the win is
    // declared by itself so it is normally not seen there.
    final showWin =
        scores[playerOrTeamIndex] >= 3 &&
        _matchWinnerIndex == null &&
        !_editMode;
    final mirrored = playerOrTeamIndex.isOdd;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showWin && mirrored)
          _buildWinTick(playerOrTeamIndex, mirrored: true),
        ..._buildTickBars(playerOrTeamIndex),
        if (showWin && !mirrored)
          _buildWinTick(playerOrTeamIndex, mirrored: false),
        if (_editMode) ...[
          const SizedBox(width: 10),
          _buildTickEditButton(playerOrTeamIndex, -1),
          _buildTickEditButton(playerOrTeamIndex, 1),
        ],
      ],
    );
  }

  List<Widget> _buildTickBars(int playerOrTeamIndex) {
    return List.generate(3, (i) {
      bool isFilled = i < scores[playerOrTeamIndex];

      // Points are no longer added by tapping them: they come from battle
      // results, or from the + / - of the edit mode.
      return Transform(
        transform: Matrix4.skewX(-0.25),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 35,
          // Increased
          height: 55,
          // Increased
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isFilled
                  ? [
                      Colors.cyanAccent,
                      Colors.purpleAccent.withValues(alpha: 0.8),
                    ]
                  : [Colors.blueGrey.withValues(alpha: 0.4), Colors.black87],
            ),
            border: Border.all(
              color: isFilled ? Colors.cyanAccent : Colors.white10,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(2),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.6),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
        ),
      );
    });
  }

  Widget _buildMatchWinnerOverlay() {
    final winnerIndex = _matchWinnerIndex!;
    final title = widget.isTeamBattle
        ? 'TEAM ${winnerIndex + 1} WON!'
        : '${widget.players[winnerIndex].name.toUpperCase()} WON!';

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Offset>(
                tween: Tween<Offset>(
                  begin: const Offset(-1.2, 0),
                  end: Offset.zero,
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, offset, child) {
                  return Transform.translate(
                    offset: Offset(offset.dx * 460, 0),
                    child: child,
                  );
                },
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 62,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 3,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        offset: Offset(4, 4),
                        blurRadius: 10,
                      ),
                      Shadow(color: Colors.white24, blurRadius: 24),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Transform.scale(
                scale: 1.1,
                child: widget.isTeamBattle
                    ? _buildTeamWinnerPanel(winnerIndex)
                    : _buildSoloWinnerPanel(winnerIndex),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // In every mode (also auto, just in case).
                  FramedActionButton(
                    text: 'KEEP BRAWLING',
                    icon: Icons.undo_rounded,
                    gradient: _solidFrame(const Color(0xFF3FD0DC)),
                    onPressed: _undoMatchWin,
                    width: 420,
                    height: 80,
                    textFontSize: 24,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 18),
                  FramedActionButton(
                    icon: Icons.arrow_forward_ios_rounded,
                    gradient: _solidFrame(const Color(0xFFFFC107)),
                    accentColor: Colors.amberAccent,
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        _fadeRoute(const MainMenuScreen()),
                        (route) => false,
                      );
                    },
                    width: 110,
                    height: 80,
                    iconSize: 40,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoloWinnerPanel(int playerIndex) {
    final player = widget.players[playerIndex];
    final isRed = playerIndex.isOdd;
    final themeColor = _playerThemeColor(playerIndex, isTeamBattle: false);

    return PlayerArenaInfo(
      player: player,
      isMirrored: playerIndex.isOdd,
      themeColor: themeColor,
      extra: !widget.isTeamBattle ? _buildTicks(playerIndex) : null,
      isSelected: isRed,
      gradient: _playerGradient(playerIndex, isTeamBattle: false),
      glowAlpha: 0.7,
      thickness: 6.0,
      isSelecting: false,
      isExpanded: true,
    );
  }

  Widget _buildTeamWinnerPanel(int teamIndex) {
    final firstIndex = teamIndex == 0 ? 0 : 1;
    final secondIndex = teamIndex == 0 ? 2 : 3;
    final isMirrored = teamIndex == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMirrored
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        _buildWinnerTeamPlayer(firstIndex, isMirrored),
        const SizedBox(height: 24),
        Padding(
          padding: EdgeInsets.only(
            left: isMirrored ? 0 : 90,
            right: isMirrored ? 90 : 0,
          ),
          child: _buildWinnerTeamPlayer(secondIndex, isMirrored),
        ),
        const SizedBox(height: 30),
        Align(
          alignment: isMirrored ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: isMirrored ? 0 : 120,
              right: isMirrored ? 120 : 0,
            ),
            child: _buildTicks(teamIndex),
          ),
        ),
      ],
    );
  }

  Widget _buildWinnerTeamPlayer(int playerIndex, bool isMirrored) {
    final player = widget.players[playerIndex];
    final isRed = playerIndex.isOdd;
    final themeColor = isRed ? Colors.redAccent : Colors.blueAccent;

    return PlayerArenaInfo(
      player: player,
      isMirrored: isMirrored,
      themeColor: themeColor,
      isSelected: isRed,
      gradient: _playerGradient(playerIndex, isTeamBattle: true),
      glowAlpha: 0.7,
      thickness: 6.0,
      isSelecting: false,
      isExpanded: true,
    );
  }
}

class GPowerBadge extends StatelessWidget {
  final int gPower;
  final String attribute;
  final Color themeColor;

  const GPowerBadge({
    super.key,
    required this.gPower,
    required this.attribute,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    const double nudgeX = -1.0; // Positive = Right, Negative = Left
    const double nudgeY =
        -1.0; // Positive = Down, Negative = Up (Try -2.0 or -3.0)
    const double iconSize = 80.0; // Total size of the PNG icon

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          // 1. THE SKEWED BAR
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.15),
            child: Container(
              width: 280,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    themeColor.withValues(alpha: 0.9),
                    themeColor.withValues(alpha: 0.4),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: 25,
                    top: 8,
                    bottom: 0,
                    width: 170,
                    child: Container(
                      alignment: Alignment.centerRight,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.skewX(0.15),
                        child: AutoSizeText(
                          '$gPower',
                          maxLines: 1,
                          minFontSize: 28,
                          stepGranularity: 0.5,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            fontSize: 55,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            letterSpacing: -2,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                offset: Offset(3, 3),
                                blurRadius: 4,
                              ),
                              Shadow(color: Colors.white24, blurRadius: 15),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. THE UPDATED ORB CODE
          Positioned(
            left: -35,
            child: Container(
              width: 95,
              height: 95,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.2, -0.3),
                  colors: [Colors.white, Colors.grey, Color(0xFF1A1A1A)],
                  stops: [0.0, 0.4, 1.0],
                ),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 15,
                    offset: const Offset(4, 4),
                  ),
                ],
              ),
              child: Center(
                // Transform.translate is the "nuclear option" for alignment
                // It will move the PNG regardless of BoxFit or Center rules
                child: Transform.translate(
                  offset: const Offset(nudgeX, nudgeY),
                  child: SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: Image.asset(
                      'assets/images/attributes/${attribute}_game.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InteractiveCard extends StatefulWidget {
  final String imagePath;
  final VoidCallback? onTap;
  final double width;

  const InteractiveCard({
    super.key,
    required this.imagePath,
    this.onTap,
    this.width = 400,
  });

  @override
  State<InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<InteractiveCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) {
          setState(() => _isHovered = false);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: _isHovered ? 0.3 : 0.2),
                  blurRadius: _isHovered ? 40 : 25,
                  spreadRadius: _isHovered ? 8 : 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset(widget.imagePath, width: widget.width),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchAbilityMiniCard extends StatefulWidget {
  final String imagePath;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MatchAbilityMiniCard({
    required this.imagePath,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_MatchAbilityMiniCard> createState() => _MatchAbilityMiniCardState();
}

class _MatchAbilityMiniCardState extends State<_MatchAbilityMiniCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final opacity = widget.isActive ? 1.0 : 0.48;
    final glowOpacity = _isHovered ? 0.26 : 0.16;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isHovered ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: opacity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: glowOpacity),
                    blurRadius: _isHovered ? 24 : 18,
                    spreadRadius: _isHovered ? 2 : 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(widget.imagePath, width: 90),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WinTick extends StatefulWidget {
  final bool mirrored;
  final VoidCallback onPressed;

  const _WinTick({required this.mirrored, required this.onPressed});

  @override
  State<_WinTick> createState() => _WinTickState();
}

class _WinTickState extends State<_WinTick> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC107);
    final scale = _pressed ? 1.14 : (_hovered ? 1.08 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.25),
            child: Container(
              width: 72,
              height: 55,
              // Extra gap on the side that faces the bars (the skew eats the
              // normal one).
              margin: EdgeInsets.only(
                left: widget.mirrored ? 4 : 16,
                right: widget.mirrored ? 16 : 4,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE082), Color(0xFFFF8F00)],
                ),
                border: Border.all(color: gold, width: 3),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: gold.withValues(alpha: _hovered ? 0.95 : 0.75),
                    blurRadius: _hovered ? 26 : 18,
                    spreadRadius: _hovered ? 3 : 2,
                  ),
                ],
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(0.25),
                child: const Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'WIN?',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        shadows: [Shadow(color: Colors.white54, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
