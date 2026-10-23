part of '../../main.dart';

class CardCatalogEntry {
  final String key;
  final String name;
  final String type;
  final String cardClass;
  final String imagePath;
  final String descriptionEn;
  final String descriptionEs;
  final Map<String, int> attributes;
  // 'global' or 'owner' for cards that stay in effect while in a used pile.
  final String? persistent;

  const CardCatalogEntry({
    required this.key,
    required this.name,
    required this.type,
    required this.cardClass,
    required this.imagePath,
    required this.descriptionEn,
    required this.descriptionEs,
    required this.attributes,
    this.persistent,
  });

  String descriptionFor(AppLanguage lang) {
    if (lang == AppLanguage.es) {
      return descriptionEs.trim().isNotEmpty ? descriptionEs : descriptionEn;
    } else {
      return descriptionEn.trim().isNotEmpty ? descriptionEn : descriptionEs;
    }
  }

  String get description =>
      descriptionFor(LanguageController.instance.cardLanguage);

  String get typeLabel => type == 'gate' ? 'GATE CARD' : 'ABILITY CARD';
}

Future<List<CardCatalogEntry>> loadCardCatalog() async {
  const jsonPaths = [
    'assets/images/cards/cards.json',
    'assets/images/cards/cards_expansion.json',
  ];
  final cards = <String, dynamic>{};
  for (final jsonPath in jsonPaths) {
    final decoded = jsonDecode(await rootBundle.loadString(jsonPath));
    if (decoded is! Map || decoded['cards'] is! Map) continue;
    cards.addAll(Map<String, dynamic>.from(decoded['cards'] as Map));
  }

  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest
      .listAssets()
      .where(
        (asset) =>
            asset.startsWith('assets/images/cards/') &&
            asset != 'assets/images/cards/anverse.png' &&
            asset.endsWith('.png'),
      )
      .toList();

  final result = <CardCatalogEntry>[];
  for (final entry in cards.entries) {
    if (entry.value is! Map) continue;
    final data = Map<String, dynamic>.from(entry.value as Map);
    final name = (data['name'] ?? '').toString().trim();
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (name.isEmpty || (type != 'gate' && type != 'ability')) continue;

    final descriptionsRaw = data['descriptions'];
    final descriptions = descriptionsRaw is Map
        ? Map<String, dynamic>.from(descriptionsRaw)
        : const <String, dynamic>{};
    final attributes = <String, int>{};
    final rawAttributes = data['attributes'];
    if (rawAttributes is Map) {
      for (final attribute in rawAttributes.entries) {
        final value = attribute.value is num
            ? (attribute.value as num).toInt()
            : int.tryParse(attribute.value.toString());
        if (value != null) {
          attributes[attribute.key.toString().toLowerCase()] = value;
        }
      }
    }

    result.add(
      CardCatalogEntry(
        key: entry.key,
        name: name,
        type: type,
        cardClass: (data['card_class'] ?? '').toString().toLowerCase(),
        imagePath:
            _matchCardImagePath(
              cardKey: entry.key,
              cardName: name,
              assetPaths: assets,
              fileName: data['file']?.toString(),
            ) ??
            'assets/images/cards/anverse.png',
        descriptionEn: descriptions['en']?.toString() ?? '',
        descriptionEs: descriptions['es']?.toString() ?? '',
        attributes: attributes,
        persistent: data['persistent']?.toString(),
      ),
    );
  }

  result.sort((a, b) {
    final typeCompare = a.type.compareTo(b.type);
    if (typeCompare != 0) return typeCompare;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return result;
}

Color _inventoryCardAccent(CardCatalogEntry card) {
  final palette = card.type == 'gate'
      ? _gateDescriptionAccentColors
      : _abilityDescriptionAccentColors;
  final fallback = card.type == 'gate' ? 'silver' : 'blue';
  return palette[card.cardClass] ?? palette[fallback]!;
}

List<Color> _inventoryCardGradient(CardCatalogEntry card) {
  final palette = card.type == 'gate'
      ? _gateDescriptionBorderGradients
      : _abilityDescriptionBorderGradients;
  final fallback = card.type == 'gate' ? 'silver' : 'blue';
  return palette[card.cardClass] ?? palette[fallback]!;
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  Map<String, int> _savedGPowerByInventoryKey = <String, int>{};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_playStoreMusic());
    unawaited(_loadInventory());
  }

  Future<void> _playStoreMusic() async {
    try {
      await _bgMusicPlayer.stop();
      await _setAppPlayerBaseVolume(_bgMusicPlayer, 0.3);
      await _bgMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgMusicPlayer.play(AssetSource('music/menu/Store.mp3'));
    } catch (error, stackTrace) {
      debugPrint('Inventory music could not be played: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _loadInventory() async {
    await loadAvailableBakugans();
    final store = await LeaderboardRepository.instance.loadStore();
    final savedGPower = {
      for (final entry in store.bakuganInventory.bakugans)
        if (entry.gPower > 0) entry.inventoryKey: entry.gPower,
    };
    if (!mounted) return;
    setState(() {
      _savedGPowerByInventoryKey = savedGPower;
      _isLoading = false;
    });
  }

  Future<void> _openBakuganCarousel() async {
    await Navigator.of(context).push(
      _zoomRoute(
        BakuganInventoryCarouselScreen(
          bakugans: availableBakugans,
          initialGPowerByInventoryKey: _savedGPowerByInventoryKey,
          onInventoryChanged: (activeVariants) {
            if (!mounted) return;
            setState(() {
              _savedGPowerByInventoryKey = {
                for (final variant in activeVariants)
                  bakuganVariantKey(variant): variant.gPower,
              };
            });
          },
        ),
      ),
    );
  }

  Future<void> _openCardsScreen() async {
    await Navigator.of(context).push(_zoomRoute(const InventoryCardsScreen()));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _inventoryBackground(
        const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return _inventoryBackground(
      SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildInventoryEntryPoints()),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryEntryPoints() {
    final compact = MediaQuery.sizeOf(context).width < 1200;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InventoryEntryButton(
                      label: 'BAKUGAN',
                      subtitle: 'Manage the Bakugan available in selection',
                      color: Colors.cyanAccent,
                      gradient: _inventoryCyanGradient,
                      emblem: Transform.scale(
                        // The ball has a lot of empty margin: draw it bigger.
                        scale: 1.35,
                        child: Image.asset(
                          'assets/models/Season_1_Battle_Brawlers/Dragonoid/Cartoon/pyrus.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      onTap: _openBakuganCarousel,
                    ),
                    const SizedBox(height: 22),
                    _InventoryEntryButton(
                      label: 'CARDS',
                      subtitle: 'Browse every card in the app',
                      color: Colors.amberAccent,
                      gradient: _gateDescriptionBorderGradients['gold']!,
                      emblem: Image.asset(
                        'assets/frames/Final Silver Frame.png',
                        fit: BoxFit.contain,
                      ),
                      onTap: _openCardsScreen,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _InventoryEntryButton(
                        label: 'BAKUGAN',
                        subtitle: 'Manage the Bakugan available in selection',
                        color: Colors.cyanAccent,
                        gradient: _inventoryCyanGradient,
                        emblem: Transform.scale(
                          // The ball has a lot of empty margin: draw it bigger.
                          scale: 1.35,
                          child: Image.asset(
                            'assets/models/Season_1_Battle_Brawlers/Dragonoid/Cartoon/pyrus.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        onTap: _openBakuganCarousel,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _InventoryEntryButton(
                        label: 'CARDS',
                        subtitle: 'Browse every card in the app',
                        color: Colors.amberAccent,
                        gradient: _gateDescriptionBorderGradients['gold']!,
                        emblem: Image.asset(
                          'assets/frames/Final Silver Frame.png',
                          fit: BoxFit.contain,
                        ),
                        onTap: _openCardsScreen,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _inventoryBackground(Widget child) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/inventory_bg.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              unawaited(_playUiCancelSound());
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INVENTORY',
                  style: TextStyle(
                    fontFamily: 'title_font',
                    fontSize: 46,
                    color: Colors.white,
                    letterSpacing: 2,
                    shadows: [Shadow(color: Colors.cyan, blurRadius: 18)],
                  ),
                ),
                Text(
                  'BUILD YOUR COLLECTION  /  EXPLORE THE LIBRARY',
                  style: TextStyle(
                    fontFamily: 'button_font',
                    color: Colors.white60,
                    fontSize: 12,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const List<Color> _inventoryCyanGradient = [
  Color(0xFF0C3B42),
  Color(0xFF27AEB9),
  Color(0xFF8CEBF2),
  Color(0xFF082A2F),
];

class _InventoryEntryButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final List<Color> gradient;
  final Widget emblem;
  final VoidCallback onTap;

  const _InventoryEntryButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.gradient,
    required this.emblem,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        unawaited(_playUiConfirmSound());
        onTap();
      },
      child: FramedPanelFrame(
        height: 260,
        frameGradient: gradient,
        accentColor: color,
        childSkew: 0.12,
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: emblem),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: 'button_font',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'button_font',
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryFilterTab extends StatelessWidget {
  static const List<Color> _neutralGradient = [
    Color(0xFF2A2F36),
    Color(0xFF4A5059),
    Color(0xFF2A2F36),
  ];

  static const List<Color> _activeGradient = [
    Color(0xFF5A606A),
    Color(0xFF9AA1AC),
    Color(0xFF5A606A),
  ];

  final String label;
  final IconData icon;
  final String? leadingAsset;
  final Color accentColor;
  final bool active;
  final bool enabled;
  final bool dropdown;
  final double height;
  final VoidCallback onTap;

  const _InventoryFilterTab({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.height,
    required this.onTap,
    this.leadingAsset,
    this.active = false,
    this.enabled = true,
    this.dropdown = false,
  });

  @override
  Widget build(BuildContext context) {
    // Never tinted: an active tab just gets a brighter neutral border.
    final gradient = active ? _activeGradient : _neutralGradient;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: const Duration(milliseconds: 160),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.15),
          child: Container(
            height: height,
            padding: const EdgeInsets.fromLTRB(3, 3, 3, 0),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
              ),
              child: ColoredBox(
                color: const Color(0xFF05080D),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.skewX(0.15),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leadingAsset != null)
                          Image.asset(
                            leadingAsset!,
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                          )
                        else
                          Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'button_font',
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        if (dropdown) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.expand_more_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ],
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

class InventoryCardsScreen extends StatefulWidget {
  const InventoryCardsScreen({super.key});

  @override
  State<InventoryCardsScreen> createState() => _InventoryCardsScreenState();
}

class _InventoryCardsScreenState extends State<InventoryCardsScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final Future<List<CardCatalogEntry>> _cardsFuture;
  String _query = '';
  final Set<String> _selectedClasses = <String>{};
  bool _onlyPersistent = false;

  @override
  void initState() {
    super.initState();
    _cardsFuture = loadCardCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CardCatalogEntry> _filteredCards(List<CardCatalogEntry> cards) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty && _selectedClasses.isEmpty && !_onlyPersistent) {
      return cards;
    }
    return cards
        .where(
          (card) =>
              (!_onlyPersistent || card.persistent != null) &&
              (_selectedClasses.isEmpty ||
                  _selectedClasses.contains(card.cardClass)) &&
              (card.name.toLowerCase().contains(query) ||
                  card.typeLabel.toLowerCase().contains(query) ||
                  card.description.toLowerCase().contains(query)),
        )
        .toList();
  }

  Widget _buildSearchField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search cards',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Cards that stay in effect while they are in a used pile.
        GestureDetector(
          onTap: () {
            unawaited(_playUiConfirmSound());
            setState(() => _onlyPersistent = !_onlyPersistent);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _onlyPersistent
                  ? Colors.amberAccent
                  : Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _onlyPersistent ? Colors.amberAccent : Colors.white38,
              ),
            ),
            child: Text(
              'PERSISTENT',
              style: TextStyle(
                color: _onlyPersistent ? Colors.black : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AsyncSnapshot<List<CardCatalogEntry>> snapshot) {
    if (!snapshot.hasData && !snapshot.hasError) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amberAccent),
      );
    }
    return _CardCarousel(
      cards: snapshot.hasData
          ? _filteredCards(snapshot.data!)
          : const <CardCatalogEntry>[],
      searchField: _buildSearchField(),
      selectedClasses: _selectedClasses,
      onToggleClass: (cardClass) => setState(() {
        final wasSelected = _selectedClasses.contains(cardClass);
        _selectedClasses.clear();
        if (!wasSelected) _selectedClasses.add(cardClass);
      }),
      emptyMessage: snapshot.hasError
          ? 'CARD LIBRARY UNAVAILABLE\n${snapshot.error}'
          : 'NO CARDS MATCH YOUR SEARCH',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/inventory_bg.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            unawaited(_playUiCancelSound());
                            Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'CARD LIBRARY',
                            style: TextStyle(
                              fontFamily: 'title_font',
                              fontSize: 42,
                              color: Colors.white,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(color: Colors.amber, blurRadius: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<CardCatalogEntry>>(
                      future: _cardsFuture,
                      builder: (context, snapshot) => _buildBody(snapshot),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skewed framed panel with the search bar on top. When [card] is null a
/// neutral frame is used.
class _CardLibraryFrame extends StatelessWidget {
  final CardCatalogEntry? card;
  final Widget searchField;
  final Widget body;
  final double? width;
  final double? height;

  const _CardLibraryFrame({
    required this.card,
    required this.searchField,
    required this.body,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final accent = card == null
        ? Colors.amberAccent
        : _inventoryCardAccent(card!);
    final gradient = card == null
        ? _gateDescriptionBorderGradients['silver']!
        : _inventoryCardGradient(card!);
    return FramedPanelFrame(
      width: width,
      height: height,
      frameGradient: gradient,
      accentColor: accent,
      childSkew: 0,
      child: Column(
        children: [
          Row(
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(0.12),
                child: Icon(Icons.search_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(child: searchField),
            ],
          ),
          Container(height: 1.2, color: accent.withValues(alpha: 0.28)),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _FrameTab extends StatelessWidget {
  static const List<Color> _neutralGradient = [
    Color(0xFF2A2F36),
    Color(0xFF4A5059),
    Color(0xFF2A2F36),
  ];
  static const Duration _duration = Duration(milliseconds: 240);

  final String cardClass;
  final double height;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  const _FrameTab({
    required this.cardClass,
    required this.height,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  BoxDecoration _borderDecoration(List<Color> colors) {
    return BoxDecoration(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classGradient =
        _gateDescriptionBorderGradients[cardClass] ??
        _abilityDescriptionBorderGradients[cardClass]!;
    final name = cardClass[0].toUpperCase() + cardClass.substring(1);
    final width = height;
    return GestureDetector(
      onTap: onTap,
      // The selected tab sinks into the panel's top border, which has the
      // same colour, so both read as one shape.
      child: AnimatedSlide(
        offset: Offset(0, selected ? 4 / height : 0),
        duration: _duration,
        curve: Curves.easeOutCubic,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.12),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: _duration,
                  decoration: _borderDecoration(
                    selected ? classGradient : _neutralGradient,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(3, 3, 3, 0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    child: ColoredBox(
                      color: const Color(0xFF05080D),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 11, 24, 11),
                            child: AnimatedScale(
                              scale: selected ? 1.04 : 1,
                              duration: _duration,
                              curve: Curves.easeOutBack,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.skewX(0.12),
                                child: Image.asset(
                                  'assets/frames/Final $name Frame.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: dimmed ? 0.55 : 0,
                              duration: _duration,
                              child: const ColoredBox(color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Fades the tab's dark fill into the panel so no seam shows
                // where the selected tab meets it.
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: -10,
                  height: 10,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: _duration,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF05080D), Color(0x0005080D)],
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
    );
  }
}

class _CardCarousel extends StatefulWidget {
  final List<CardCatalogEntry> cards;
  final Widget searchField;
  final Set<String> selectedClasses;
  final ValueChanged<String> onToggleClass;
  final String emptyMessage;

  const _CardCarousel({
    required this.cards,
    required this.searchField,
    required this.selectedClasses,
    required this.onToggleClass,
    required this.emptyMessage,
  });

  @override
  State<_CardCarousel> createState() => _CardCarouselState();
}

class _CardCarouselState extends State<_CardCarousel> {
  late final PageController _controller;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 1 / 3);
  }

  @override
  void didUpdateWidget(covariant _CardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cards != widget.cards) {
      _selectedIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _arrowButton({
    required IconData icon,
    required bool visible,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: visible ? 1 : 0,
      child: IgnorePointer(ignoring: !visible, child: _arrowIcon(icon, onTap)),
    );
  }

  Widget _arrowIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      iconSize: 52,
      icon: Icon(icon),
      color: Colors.white70,
      onPressed: () {
        if (!_controller.hasClients) return;
        unawaited(_playUiConfirmSound());
        onTap();
      },
    );
  }

  Widget _buildCardPager() {
    return PageView.builder(
      controller: _controller,
      itemCount: widget.cards.length,
      onPageChanged: (index) {
        setState(() => _selectedIndex = index);
        unawaited(_playUiConfirmSound());
      },
      itemBuilder: (context, index) {
        final item = widget.cards[index];
        final selected = index == _selectedIndex;
        return LayoutBuilder(
          builder: (context, itemConstraints) {
            final cardWidth = min(
              itemConstraints.maxHeight * 0.92 * _gateCardAspectRatio,
              itemConstraints.maxWidth * 0.9,
            );
            final nearby = (index - _selectedIndex).abs() <= 1;
            return AnimatedOpacity(
              opacity: nearby ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !nearby,
                child: AnimatedScale(
                  scale: selected ? 1 : 0.8,
                  duration: const Duration(milliseconds: 180),
                  child: Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.skewX(0.12),
                      child: InteractiveCard(
                        imagePath: item.imagePath,
                        width: cardWidth,
                        onTap: () {
                          if (!selected) {
                            _controller.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDescription(CardCatalogEntry card, Color accent) {
    // Same gap above the title as below the text (the panel supplies the
    // bottom padding).
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1.6,
                    shadows: [
                      Shadow(
                        color: accent.withValues(alpha: 0.30),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                '${card.typeLabel}  /  ${card.cardClass.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          Container(
            height: 1.2,
            margin: const EdgeInsets.only(top: 4, bottom: 18),
            color: accent.withValues(alpha: 0.28),
          ),
          AutoSizeText(
            card.description.isEmpty
                ? AppLocalizations.current.noDescription
                : card.description,
            maxLines: 4,
            minFontSize: 10,
            stepGranularity: 0.5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              height: 1.28,
              shadows: const [
                Shadow(
                  color: Colors.black87,
                  offset: Offset(1, 1),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _frameClasses = [
    'copper',
    'silver',
    'gold',
    'blue',
    'green',
    'red',
  ];

  Widget _buildClassTabs(double height) {
    // Neighbouring tabs overlap by one border width so they share that edge
    // instead of showing two borders side by side; the selected tab paints
    // last so its border stays on top.
    const borderWidth = 3.0;
    final step = height - borderWidth;
    final ordered = [
      ..._frameClasses.where((c) => !widget.selectedClasses.contains(c)),
      ..._frameClasses.where(widget.selectedClasses.contains),
    ];
    return SizedBox(
      width: step * _frameClasses.length + borderWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final cardClass in ordered)
            Positioned(
              key: ValueKey(cardClass),
              left: _frameClasses.indexOf(cardClass) * step,
              top: 0,
              child: _FrameTab(
                cardClass: cardClass,
                height: height,
                selected: widget.selectedClasses.contains(cardClass),
                dimmed:
                    widget.selectedClasses.isNotEmpty &&
                    !widget.selectedClasses.contains(cardClass),
                onTap: () {
                  unawaited(_playUiConfirmSound());
                  widget.onToggleClass(cardClass);
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCards = widget.cards.isNotEmpty;
    final card = hasCards
        ? widget.cards[_selectedIndex.clamp(0, widget.cards.length - 1)]
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 12),
      child: Row(
        children: [
          _arrowButton(
            icon: Icons.arrow_back_ios_rounded,
            visible: hasCards && _selectedIndex > 0,
            onTap: () => _controller.previousPage(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The panel skew shifts its corners sideways by 0.06 * height.
                const tabHeight = 112.0;
                final panelHeight = constraints.maxHeight * 0.8;
                // The panel skew shifts its corners sideways by 0.06 * height.
                final skewAllowance = panelHeight * 0.12;
                final panelWidth = min(
                  1300.0,
                  constraints.maxWidth - skewAllowance,
                );
                return Center(
                  // Taller than the panel so the tabs stay inside the hit
                  // area; shifted back up so the panel keeps its position.
                  child: Transform.translate(
                    offset: const Offset(0, -tabHeight / 2),
                    child: SizedBox(
                      width: panelWidth + skewAllowance + 6,
                      height: panelHeight + tabHeight,
                      child: Stack(
                        children: [
                          Positioned(
                            left: skewAllowance / 2,
                            bottom: 0,
                            child: _CardLibraryFrame(
                              card: card,
                              searchField: widget.searchField,
                              width: panelWidth,
                              height: panelHeight,
                              body: card == null
                                  ? Center(
                                      child: Text(
                                        widget.emptyMessage,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontFamily: 'button_font',
                                          letterSpacing: 1.3,
                                        ),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        Expanded(child: _buildCardPager()),
                                        _buildDescription(
                                          card,
                                          _inventoryCardAccent(card),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 15,
                            child: _buildClassTabs(tabHeight),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _arrowButton(
            icon: Icons.arrow_forward_ios_rounded,
            visible: hasCards && _selectedIndex < widget.cards.length - 1,
            onTap: () => _controller.nextPage(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            ),
          ),
        ],
      ),
    );
  }
}

class BakuganInventoryCarouselScreen extends StatefulWidget {
  final List<Bakugan> bakugans;
  final Map<String, int>? initialGPowerByInventoryKey;
  final ValueChanged<List<BakuganVariant>>? onInventoryChanged;

  const BakuganInventoryCarouselScreen({
    super.key,
    required this.bakugans,
    this.initialGPowerByInventoryKey,
    this.onInventoryChanged,
  });

  @override
  State<BakuganInventoryCarouselScreen> createState() =>
      _BakuganInventoryCarouselScreenState();
}

class _BakuganInventoryCarouselScreenState
    extends State<BakuganInventoryCarouselScreen> {
  final PageController _carouselController = PageController(
    viewportFraction: 0.14,
  );
  static const List<String> _attributeWheelOrder = [
    'pyrus',
    'subterra',
    'haos',
    'darkus',
    'aquos',
    'ventus',
  ];

  int _selectedBakuganIndex = 0;
  int _selectedVariantIndex = 0;
  String? _selectedAttribute;
  _BakuganSortMode _sortMode = _BakuganSortMode.alphabetical;
  bool _collectionMode = false;
  final Map<String, int> _gPowerOverrides = <String, int>{};
  Future<void> _saveQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _gPowerOverrides.addAll(widget.initialGPowerByInventoryKey ?? const {});
  }

  List<BakuganVariant> get _allVariants => [
    for (final bakugan in widget.bakugans) ...bakugan.variants,
  ];

  BakuganVariant _effectiveVariant(BakuganVariant variant) {
    final override = _gPowerOverrides[bakuganVariantKey(variant)];
    return override == null ? variant : variant.copyWith(gPower: override);
  }

  List<BakuganVariant> get _activeVariants => [
    for (final variant in _allVariants)
      if (_isVariantOwned(variant)) _effectiveVariant(variant),
  ];

  bool _isVariantOwned(BakuganVariant variant) {
    return (_gPowerOverrides[bakuganVariantKey(variant)] ?? 0) > 0;
  }

  void _setCollectionMode(bool enabled) {
    if (_collectionMode == enabled) return;
    unawaited(_playUiConfirmSound());
    final currentBakugans = _visibleBakugans;
    final currentSpeciesName = _selectedBakuganIndex < currentBakugans.length
        ? currentBakugans[_selectedBakuganIndex].name
        : null;
    setState(() {
      _collectionMode = enabled;
      _syncSelection(preferredSpeciesName: currentSpeciesName);
    });
  }

  Future<void> _clearAllGPower() async {
    if (_activeVariants.isEmpty) return;
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Clear all G-Power',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final modal = BakuganModal(
          title: 'CLEAR ALL G POWER',
          icon: Icons.delete_sweep_rounded,
          accentColor: Colors.redAccent,
          solidBorder: true,
          width: 640,
          contentPadding: const EdgeInsets.fromLTRB(48, 0, 48, 8),
          edgePadding: const EdgeInsets.fromLTRB(32, 0, 40, 0),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: const Text(
            'This removes every saved G-Power from your collection. '
            'Your Bakugan stay in the list, but will count as not owned '
            'until you set their G-Power again.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          actions: [
            BakuganModalActionButton(
              text: 'CANCEL',
              color: Colors.white70,
              useCancelSound: true,
              showGrid: false,
              useGradientBorder: false,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            BakuganModalActionButton(
              text: 'CLEAR ALL',
              color: Colors.redAccent,
              showGrid: false,
              useGradientBorder: false,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
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
              Center(child: modal),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final currentBakugans = _visibleBakugans;
    final currentSpeciesName = _selectedBakuganIndex < currentBakugans.length
        ? currentBakugans[_selectedBakuganIndex].name
        : null;
    setState(() {
      for (final variant in _allVariants) {
        _gPowerOverrides[bakuganVariantKey(variant)] = 0;
      }
      _syncSelection(preferredSpeciesName: currentSpeciesName);
    });
    _queueInventorySave();
  }

  void _queueInventorySave() {
    final snapshot = _activeVariants.toList();
    widget.onInventoryChanged?.call(snapshot);
    _saveQueue = _saveQueue.then((_) async {
      await LeaderboardRepository.instance.saveBakuganInventory(snapshot);
    });
  }

  Bakugan _effectiveBakugan(Bakugan bakugan) {
    return Bakugan(
      name: bakugan.name,
      variants: bakugan.variants.map(_effectiveVariant).toList(),
    );
  }

  List<Bakugan> get _visibleBakugans {
    final allBakugans = widget.bakugans.map(_effectiveBakugan).toList();
    final sourceBakugans = _collectionMode
        ? allBakugans
              .map(
                (bakugan) => Bakugan(
                  name: bakugan.name,
                  variants: bakugan.variants.where(_isVariantOwned).toList(),
                ),
              )
              .where((bakugan) => bakugan.variants.isNotEmpty)
              .toList()
        : allBakugans;
    final visible = sourceBakugans
        .where(
          (bakugan) =>
              _selectedAttribute == null ||
              bakugan.variants.any(
                (variant) =>
                    variant.attribute.toLowerCase() == _selectedAttribute,
              ),
        )
        .toList();

    visible.sort((a, b) {
      switch (_sortMode) {
        case _BakuganSortMode.alphabetical:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _BakuganSortMode.gPowerAsc:
          return _primaryVariantForSpecies(
            a,
          ).gPower.compareTo(_primaryVariantForSpecies(b).gPower);
        case _BakuganSortMode.gPowerDesc:
          return _primaryVariantForSpecies(
            b,
          ).gPower.compareTo(_primaryVariantForSpecies(a).gPower);
      }
    });
    return visible;
  }

  Bakugan get _currentBakugan => _visibleBakugans[_selectedBakuganIndex];
  BakuganVariant get _currentVariant =>
      _currentBakugan.variants[_selectedVariantIndex];

  int _preferredVariantIndex(Bakugan species) {
    if (_selectedAttribute == null) return 0;
    final index = species.variants.indexWhere(
      (variant) => variant.attribute.toLowerCase() == _selectedAttribute,
    );
    return index >= 0 ? index : 0;
  }

  BakuganVariant _primaryVariantForSpecies(Bakugan species) {
    return species.variants[_preferredVariantIndex(species)];
  }

  void _syncSelection({String? preferredSpeciesName}) {
    final visibleBakugans = _visibleBakugans;
    if (visibleBakugans.isEmpty) {
      _selectedBakuganIndex = 0;
      _selectedVariantIndex = 0;
      return;
    }

    final currentSpeciesName =
        preferredSpeciesName ??
        (_selectedBakuganIndex < visibleBakugans.length
            ? visibleBakugans[_selectedBakuganIndex].name
            : null);
    final matchingIndex = currentSpeciesName == null
        ? -1
        : visibleBakugans.indexWhere(
            (bakugan) => bakugan.name == currentSpeciesName,
          );
    _selectedBakuganIndex = matchingIndex >= 0 ? matchingIndex : 0;
    _selectedVariantIndex = _preferredVariantIndex(
      visibleBakugans[_selectedBakuganIndex],
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_carouselController.hasClients) return;
      _carouselController.jumpToPage(_selectedBakuganIndex);
    });
  }

  Color _colorForAttribute(String attribute) {
    switch (attribute.trim().toLowerCase()) {
      case 'pyrus':
        return const Color(0xFFFF6B3D);
      case 'aquos':
        return const Color(0xFF3DA5FF);
      case 'subterra':
        return const Color(0xFFD4A037);
      case 'haos':
        return const Color(0xFFF1E68A);
      case 'darkus':
        return const Color(0xFF9B59FF);
      case 'ventus':
        return const Color(0xFF45D483);
      default:
        return Colors.blueAccent;
    }
  }

  String _sortModeLabel(_BakuganSortMode mode) {
    switch (mode) {
      case _BakuganSortMode.alphabetical:
        return 'A-Z';
      case _BakuganSortMode.gPowerAsc:
        return 'LOW G';
      case _BakuganSortMode.gPowerDesc:
        return 'HIGH G';
    }
  }

  IconData _sortModeIcon(_BakuganSortMode mode) {
    switch (mode) {
      case _BakuganSortMode.alphabetical:
        return Icons.sort_by_alpha_rounded;
      case _BakuganSortMode.gPowerAsc:
        return Icons.arrow_upward_rounded;
      case _BakuganSortMode.gPowerDesc:
        return Icons.arrow_downward_rounded;
    }
  }

  bool _showsPreyasDualAttributeIcon(BakuganVariant variant) {
    return variant.speciesName.trim().toLowerCase() == 'preyas diablo' &&
        variant.attribute.toLowerCase() != 'pyrus';
  }

  Future<void> _editGPower(BakuganVariant variant) async {
    // A Bakugan without G-Power opens with an empty field (showing the "0" hint)
    // instead of a selected 0.
    final controller = TextEditingController(
      text: variant.gPower == 0 ? '' : '${variant.gPower}',
    );
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final editedText = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit G-Power',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        void save() => Navigator.of(dialogContext).pop(controller.text);

        final modal = BakuganModal(
          title: variant.speciesName.toUpperCase(),
          // The attribute logo first, then the name.
          leading: Transform.translate(
            offset: const Offset(0, 8),
            child: Image.asset(
              'assets/images/attributes/${variant.attribute}_game.png',
              width: 48,
              height: 48,
            ),
          ),
          width: 640,
          contentPadding: const EdgeInsets.fromLTRB(40, 0, 40, 0),
          edgePadding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.12),
            child: Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(0.12),
                // The value and the "G" share a baseline so they line up.
                child: Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: (_) => save(),
                          cursorColor: Colors.cyanAccent,
                          textAlignVertical: TextAlignVertical.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: '0',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'G',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            BakuganModalActionButton(
              text: 'SAVE',
              showGrid: false,
              useGradientBorder: false,
              onPressed: save,
            ),
          ],
        );

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
              Center(child: modal),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
    controller.dispose();

    final key = bakuganVariantKey(variant);
    final previousValue = _gPowerOverrides[key] ?? 0;
    final editedValue = int.tryParse(editedText?.trim() ?? '');
    if (editedValue == null || editedValue == previousValue) return;
    setState(() {
      _gPowerOverrides[key] = editedValue;
    });
    _queueInventorySave();
  }

  void _setAttributeFilter(String? attribute) {
    final currentSpeciesName =
        _visibleBakugans.isNotEmpty &&
            _selectedBakuganIndex < _visibleBakugans.length
        ? _visibleBakugans[_selectedBakuganIndex].name
        : null;
    unawaited(_playUiConfirmSound());
    setState(() {
      _selectedAttribute = attribute;
      if (attribute == null) _sortMode = _BakuganSortMode.alphabetical;
      _syncSelection(preferredSpeciesName: currentSpeciesName);
    });
  }

  void _setSortMode(_BakuganSortMode mode) {
    if (_selectedAttribute == null || _sortMode == mode) return;
    final currentSpeciesName =
        _visibleBakugans.isNotEmpty &&
            _selectedBakuganIndex < _visibleBakugans.length
        ? _visibleBakugans[_selectedBakuganIndex].name
        : null;
    unawaited(_playUiConfirmSound());
    setState(() {
      _sortMode = mode;
      _syncSelection(preferredSpeciesName: currentSpeciesName);
    });
  }

  Future<void> _openAttributePicker() async {
    unawaited(_playUiConfirmSound());
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 180,
            vertical: 110,
          ),
          child: _SelectionOverlayShell(
            title: 'FILTER BY ATTRIBUTE',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AttributeWheelPicker(
                  selectedAttribute: _selectedAttribute,
                  orderedAttributes: _attributeWheelOrder,
                  colorForAttribute: _colorForAttribute,
                  onSelectAttribute: (attribute) {
                    Navigator.of(context).pop();
                    _setAttributeFilter(attribute);
                  },
                  onClear: () {
                    Navigator.of(context).pop();
                    _setAttributeFilter(null);
                  },
                ),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 500,
                  child: Text(
                    'Tap a sector to filter by attribute.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'button_font',
                      fontSize: 12,
                      color: Colors.white54,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSortPicker() async {
    if (_selectedAttribute == null) return;
    unawaited(_playUiConfirmSound());
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 220,
            vertical: 120,
          ),
          child: _SelectionOverlayShell(
            title: 'ORDER BY',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SortChip(
                  label: 'A-Z',
                  icon: Icons.sort_by_alpha_rounded,
                  isSelected: _sortMode == _BakuganSortMode.alphabetical,
                  isEnabled: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    _setSortMode(_BakuganSortMode.alphabetical);
                  },
                ),
                const SizedBox(width: 12),
                _SortChip(
                  label: 'LOW G',
                  icon: Icons.arrow_upward_rounded,
                  isSelected: _sortMode == _BakuganSortMode.gPowerAsc,
                  isEnabled: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    _setSortMode(_BakuganSortMode.gPowerAsc);
                  },
                ),
                const SizedBox(width: 12),
                _SortChip(
                  label: 'HIGH G',
                  icon: Icons.arrow_downward_rounded,
                  isSelected: _sortMode == _BakuganSortMode.gPowerDesc,
                  isEnabled: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    _setSortMode(_BakuganSortMode.gPowerDesc);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _moveCarousel(int delta, int itemCount) {
    if (itemCount <= 1) return;
    final visibleBakugans = _visibleBakugans;
    final nextIndex = (_selectedBakuganIndex + delta + itemCount) % itemCount;
    unawaited(_playUiConfirmSound());
    setState(() {
      _selectedBakuganIndex = nextIndex;
      _selectedVariantIndex = _preferredVariantIndex(
        visibleBakugans[nextIndex],
      );
    });
    _keepSelectedBakuganVisible(
      nextIndex,
      itemCount: itemCount,
      viewportFraction: 0.14,
    );
  }

  void _selectBakugan(int index) {
    final visibleBakugans = _visibleBakugans;
    if (index < 0 || index >= visibleBakugans.length) return;
    unawaited(_playUiConfirmSound());
    setState(() {
      _selectedBakuganIndex = index;
      _selectedVariantIndex = _preferredVariantIndex(visibleBakugans[index]);
    });
  }

  void _keepSelectedBakuganVisible(
    int index, {
    required int itemCount,
    required double viewportFraction,
  }) {
    if (!_carouselController.hasClients) return;
    final firstVisibleIndex = (_carouselController.page ?? 0).floor();
    final visiblePageCount = max(1, (1 / viewportFraction).floor());
    final lastVisibleIndex = firstVisibleIndex + visiblePageCount - 1;
    final targetPage = index < firstVisibleIndex
        ? index
        : index > lastVisibleIndex
        ? index - visiblePageCount + 1
        : firstVisibleIndex;
    final boundedTargetPage = targetPage.clamp(0, itemCount - 1);
    if (boundedTargetPage == firstVisibleIndex) return;
    unawaited(
      _carouselController.animateToPage(
        boundedTargetPage,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleBakugans = _visibleBakugans;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/inventory_bg.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.redAccent.withValues(alpha: 0.18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 1800;
                  final horizontalPadding = isCompact ? 16.0 : 44.0;

                  if (visibleBakugans.isEmpty) {
                    return _buildEmptyFilteredState(
                      horizontalPadding: horizontalPadding,
                    );
                  }

                  final bakugan = _currentBakugan;
                  final carouselWidth = max(520.0, constraints.maxWidth - 128);
                  // The species carousel is nudged up over the stage area.
                  final carouselOverlap = isCompact ? 4.0 : 80.0;

                  return Column(
                    children: [
                      _buildCarouselHeader(),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, area) {
                            // Up to 540 high: the attribute rail spacing and the
                            // name plate offsets are tuned for that height.
                            final stageHeight = min(
                              540.0,
                              max(
                                360.0,
                                area.maxHeight -
                                    carouselOverlap -
                                    _filterTabHeight -
                                    8,
                              ),
                            );
                            final stageWidth = min(
                              1250.0,
                              max(720.0, constraints.maxWidth - 32),
                            );
                            // The preview frame is skewed, which pushes its top
                            // edge to the right by 0.075 * height.
                            final skewExtra = stageHeight * 0.075;
                            // Sits just above the species carousel, which is
                            // nudged up over the bottom of this area.
                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: carouselOverlap + 190,
                                ),
                                child: SizedBox(
                                  width: stageWidth + skewExtra,
                                  height: stageHeight + _filterTabHeight,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: 0,
                                        bottom: 0,
                                        child: _buildSelectionStage(
                                          bakugan: bakugan,
                                          stageWidth: stageWidth,
                                          stageHeight: stageHeight,
                                        ),
                                      ),
                                      // Flush with the right end of the frame below.
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: _buildFilterTabs(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, -carouselOverlap),
                        child: _buildSpeciesCarousel(
                          visibleBakugans: visibleBakugans,
                          width: carouselWidth,
                          height: isCompact ? 150 : 180,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: isCompact ? 8 : 12,
                          top: 4,
                        ),
                        child: Text(
                          '${visibleBakugans.length} BAKUGAN',
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'button_font',
                            fontSize: isCompact ? 9 : 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double _filterTabHeight = 56;

  Widget _buildCarouselHeader() {
    return Padding(
      // Same top and height as the app's settings button (70 x 64, 22 from
      // the top) so both line up.
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              unawaited(_playUiCancelSound());
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'BAKUGAN COLLECTION',
              style: TextStyle(
                fontFamily: 'title_font',
                fontSize: 42,
                color: Colors.white,
                letterSpacing: 2,
                shadows: [Shadow(color: Colors.cyan, blurRadius: 18)],
              ),
            ),
          ),
          // Separate from the filter tabs, beside the app's settings button
          // (which sits in the top-right corner).
          FramedActionButton(
            text: 'RESET ALL',
            icon: Icons.delete_sweep_rounded,
            gradient: _solidFrame(Colors.redAccent),
            accentColor: Colors.redAccent,
            onPressed: _activeVariants.isEmpty
                ? () {}
                : () => unawaited(_clearAllGPower()),
            width: 240,
            height: 64,
            textFontSize: 20,
            iconSize: 26,
          ),
          const SizedBox(width: 82),
        ],
      ),
    );
  }

  /// Filter tabs sitting on the top edge of the preview. Neighbouring tabs
  /// overlap by their border width so they share one edge.
  Widget _buildFilterTabs() {
    final canSort = _selectedAttribute != null;
    final tabs = <Widget>[
      _InventoryFilterTab(
        label: _selectedAttribute == null
            ? 'ATTRIBUTE: ALL'
            : 'ATTRIBUTE: ${_selectedAttribute!.toUpperCase()}',
        icon: Icons.filter_alt_rounded,
        leadingAsset: _selectedAttribute == null
            ? null
            : 'assets/images/attributes/${_selectedAttribute!}_game.png',
        accentColor: _selectedAttribute == null
            ? Colors.blueAccent
            : _colorForAttribute(_selectedAttribute!),
        active: _selectedAttribute != null,
        dropdown: true,
        height: _filterTabHeight,
        onTap: _openAttributePicker,
      ),
      _InventoryFilterTab(
        label: 'ORDER: ${_sortModeLabel(_sortMode)}',
        icon: _sortModeIcon(_sortMode),
        accentColor: Colors.blueAccent,
        active: canSort,
        enabled: canSort,
        dropdown: true,
        height: _filterTabHeight,
        onTap: _openSortPicker,
      ),
      _InventoryFilterTab(
        label: _collectionMode
            ? 'COLLECTION MODE: OWNED'
            : 'COLLECTION MODE: ALL',
        icon: _collectionMode
            ? Icons.inventory_2_rounded
            : Icons.grid_view_rounded,
        // Same colour as the preview frame so the active tab blends with it.
        accentColor: _visibleBakugans.isEmpty
            ? Colors.cyanAccent
            : _currentVariant.color,
        // Same border in both modes: the label already says OWNED / ALL.
        height: _filterTabHeight,
        onTap: () => _setCollectionMode(!_collectionMode),
      ),
      _InventoryFilterTab(
        label: 'EDIT',
        icon: Icons.edit_rounded,
        accentColor: Colors.amberAccent,
        enabled: _visibleBakugans.isNotEmpty,
        height: _filterTabHeight,
        // Edits the G-Power of the attribute that is selected.
        onTap: () => unawaited(_editGPower(_currentVariant)),
      ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tabs.length; i++)
          Transform.translate(offset: Offset(-3.0 * i, 0), child: tabs[i]),
      ],
    );
  }

  Widget _buildEmptyFilteredState({required double horizontalPadding}) {
    return Column(
      children: [
        _buildCarouselHeader(),
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8,
            horizontalPadding + 28,
            0,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: _buildFilterTabs(),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              child: _SelectionInfoPanel(
                text: _collectionMode
                    ? 'No hay Bakugan en tu colección. Desactiva COLLECTION MODE para habilitar nuevos Bakugan.'
                    : 'No hay Bakugan para este atributo.',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionStage({
    required Bakugan bakugan,
    required double stageWidth,
    required double stageHeight,
  }) {
    final attributeRailWidth = min(140.0, stageWidth * 0.16);
    final previewLeft = attributeRailWidth - 40;

    return SizedBox(
      width: stageWidth,
      height: stageHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: previewLeft,
            child: SizedBox(
              width: stageWidth - previewLeft,
              height: stageHeight,
              child: BakuganPreview(
                key: ValueKey(
                  'inventory_carousel_large_${_currentVariant.modelPath}_${_currentVariant.attribute}_${_currentVariant.texturePath}',
                ),
                variant: _currentVariant,
                isLarge: true,
                modelScale: 0.85,
                speciesName: bakugan.name,
              ),
            ),
          ),
          Positioned(
            left: 0,
            child: SizedBox(
              height: stageHeight,
              width: attributeRailWidth,
              child: _buildSelectionAttributeRail(bakugan, stageHeight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionAttributeRail(Bakugan bakugan, double stageHeight) {
    const fixedItemHeight = 90.0;
    final isFullSet = bakugan.variants.length == 6;
    return Stack(
      clipBehavior: Clip.none,
      children: bakugan.variants.asMap().entries.map((entry) {
        final index = entry.key;
        final variant = entry.value;
        final isSelected = index == _selectedVariantIndex;
        final top = isFullSet
            ? index * (stageHeight - fixedItemHeight) / 5
            : index * fixedItemHeight;
        const popOutDistance = 30.0;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: top,
          left: isSelected
              ? index * -13.5 + 35 - popOutDistance
              : index * -13.5 + 35,
          child: GestureDetector(
            onTap: () {
              unawaited(_playUiConfirmSound());
              setState(() => _selectedVariantIndex = index);
            },
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.skewX(-0.15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: isSelected ? 100 + popOutDistance : 100,
                height: fixedItemHeight,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? variant.color.withValues(alpha: 0.4)
                      : Colors.black45,
                  border: Border(
                    top: BorderSide(
                      color: isSelected ? variant.color : Colors.white24,
                      width: isSelected ? 2 : 1,
                    ),
                    left: BorderSide(
                      color: isSelected ? variant.color : Colors.white24,
                      width: isSelected ? 2 : 1,
                    ),
                    bottom: BorderSide(
                      color: isSelected ? variant.color : Colors.white24,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    bottomLeft: Radius.circular(15),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: variant.color.withValues(alpha: 0.4),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.skewX(0.15),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: 1,
                          child: _showsPreyasDualAttributeIcon(variant)
                              ? ClipRect(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/images/attributes/${variant.attribute}_game.png',
                                          fit: BoxFit.contain,
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Text(
                                            '|',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Image.asset(
                                          'assets/images/attributes/pyrus_game.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/attributes/${variant.attribute}_game.png',
                                  fit: BoxFit.contain,
                                ),
                        ),
                      ),
                      Text(
                        '${variant.gPower}G',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpeciesCarousel({
    required List<Bakugan> visibleBakugans,
    required double width,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 40),
            color: Colors.cyanAccent,
            onPressed: () => _moveCarousel(-1, visibleBakugans.length),
          ),
          SizedBox(
            width: width,
            child: PageView.builder(
              controller: _carouselController,
              padEnds: false,
              itemCount: visibleBakugans.length,
              itemBuilder: (context, index) {
                final variant = _primaryVariantForSpecies(
                  visibleBakugans[index],
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectBakugan(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: BakuganPreview(
                      key: ValueKey(
                        'inventory_carousel_thumb_${variant.modelPath}_${variant.attribute}_${variant.texturePath}',
                      ),
                      variant: variant,
                      isSelected: _selectedBakuganIndex == index,
                      speciesName: visibleBakugans[index].name,
                      gridOpacityOverride: 0.14,
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 40),
            color: Colors.cyanAccent,
            onPressed: () => _moveCarousel(1, visibleBakugans.length),
          ),
        ],
      ),
    );
  }
}
