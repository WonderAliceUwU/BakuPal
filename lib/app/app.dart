part of '../main.dart';

final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<bool> _isAppSettingsOpen = ValueNotifier<bool>(false);
// True while the scoreboard shows its own pause button next to BATTLE, so the
// app-wide settings/pause button is hidden.
final ValueNotifier<bool> _scoreboardOwnsPauseButton = ValueNotifier<bool>(
  false,
);
final ValueNotifier<MatchPauseController?> _matchPauseController =
    ValueNotifier<MatchPauseController?>(null);

class MatchPauseController {
  final Future<void> Function() onOpen;
  final Future<void> Function(String action) onAction;

  const MatchPauseController({required this.onOpen, required this.onAction});
}

class BakuganApp extends StatelessWidget {
  const BakuganApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LanguageController.instance,
      builder: (context, child) {
        return MaterialApp(
          title: 'Bakugan Stadium App',
          navigatorKey: _appNavigatorKey,
          navigatorObservers: [_HelpTopicObserver()],
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'body_font',
          ),
          builder: (context, child) {
            return LanguageScope(
              controller: LanguageController.instance,
              child: _BakuganResponsiveSurface(
                child: _AppVolumeSurface(child: child),
              ),
            );
          },
          home: const VideoSplashScreen(),
        );
      },
    );
  }
}

const Size _bakuganReferenceSize = Size(2560, 1440);
const double _bakuganUiScale = 1.10;

class _BakuganResponsiveSurface extends StatelessWidget {
  final Widget? child;

  const _BakuganResponsiveSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final virtualWidth = _bakuganReferenceSize.width / _bakuganUiScale;
        final widthScale = viewportSize.width / virtualWidth;
        final virtualHeight = viewportSize.height / widthScale;
        final virtualSize = Size(virtualWidth, virtualHeight);
        final designMediaQuery = mediaQuery.copyWith(
          size: virtualSize,
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          systemGestureInsets: EdgeInsets.zero,
        );

        return ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            child: MediaQuery(
              data: designMediaQuery,
              child: SizedBox(
                width: virtualSize.width,
                height: virtualSize.height,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}

Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    settings: RouteSettings(name: _helpTopicForPage(page)),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 600),
  );
}

class AppVolumeController extends ChangeNotifier {
  AppVolumeController._();

  static final AppVolumeController instance = AppVolumeController._();

  final Map<AudioPlayer, double> _baseVolumes = <AudioPlayer, double>{};
  final Map<VideoPlayerController, double> _videoBaseVolumes =
      <VideoPlayerController, double>{};
  double _volume = 1;
  bool _isMuted = false;

  double get volume => _volume;
  bool get isMuted => _isMuted;
  double get effectiveVolume => _isMuted ? 0 : _volume;

  Timer? _saveTimer;

  Future<void> init() async => applySettings(await _loadAppSettings());

  Future<void> applySettings(Map<String, dynamic> settings) async {
    final volume = settings['volume'];
    if (volume is num) _volume = volume.toDouble().clamp(0, 1).toDouble();
    if (settings['muted'] is bool) _isMuted = settings['muted'] as bool;
    notifyListeners();
    await _applyVolume();
  }

  // The slider calls setVolume on every move: save once it settles.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveAppSettings({'volume': _volume, 'muted': _isMuted}));
    });
  }

  void register(AudioPlayer player, {double baseVolume = 1}) {
    _baseVolumes[player] = baseVolume;
    unawaited(player.setVolume(baseVolume * effectiveVolume));
  }

  void unregister(AudioPlayer player) {
    _baseVolumes.remove(player);
  }

  void registerVideo(VideoPlayerController player, {double baseVolume = 1}) {
    _videoBaseVolumes[player] = baseVolume;
    unawaited(player.setVolume(baseVolume * effectiveVolume));
  }

  void unregisterVideo(VideoPlayerController player) {
    _videoBaseVolumes.remove(player);
  }

  Future<void> setBaseVolume(AudioPlayer player, double baseVolume) async {
    register(player, baseVolume: baseVolume);
    await player.setVolume(baseVolume * effectiveVolume);
  }

  Future<void> setVideoBaseVolume(
    VideoPlayerController player,
    double baseVolume,
  ) async {
    registerVideo(player, baseVolume: baseVolume);
    await player.setVolume(baseVolume * effectiveVolume);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 1).toDouble();
    if (_volume > 0) _isMuted = false;
    notifyListeners();
    _scheduleSave();
    await _applyVolume();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    _scheduleSave();
    await _applyVolume();
  }

  Future<void> _applyVolume() async {
    final effectiveVolume = this.effectiveVolume;
    for (final entry in _baseVolumes.entries) {
      try {
        await entry.key.setVolume(entry.value * effectiveVolume);
      } catch (_) {}
    }
    for (final entry in _videoBaseVolumes.entries) {
      try {
        await entry.key.setVolume(entry.value * effectiveVolume);
      } catch (_) {}
    }
  }
}

class _AppVolumeSurface extends StatelessWidget {
  final Widget? child;

  const _AppVolumeSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (context) => child ?? const SizedBox.shrink()),
        OverlayEntry(
          builder: (context) {
            return ListenableBuilder(
              listenable: Listenable.merge([
                _isAppSettingsOpen,
                _scoreboardOwnsPauseButton,
                _matchPauseController,
                _currentHelpTopic,
              ]),
              builder: (context, _) {
                if (_isAppSettingsOpen.value) return const SizedBox.shrink();
                // The scoreboard has its own pause button, so this one is
                // hidden there; the topic check keeps it hidden even if the
                // ownership flag went stale between screens.
                if (_scoreboardOwnsPauseButton.value ||
                    _currentHelpTopic.value == 'scoreboard') {
                  return const SizedBox.shrink();
                }
                if (_matchPauseController.value != null) {
                  return const Positioned(
                    bottom: 24,
                    right: 24,
                    child: _AppSettingsButton(isPause: true),
                  );
                }
                return const Positioned(
                  top: 22,
                  right: 24,
                  child: _AppSettingsButton(),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _AppSettingsButton extends StatelessWidget {
  final bool isPause;

  const _AppSettingsButton({this.isPause = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.settingsTitle,
      child: Material(
        type: MaterialType.transparency,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.12),
          child: Container(
            width: 70,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF090D13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: GridPainter(
                      color: Colors.cyanAccent.withValues(alpha: 0.12),
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
                          Colors.cyanAccent.withValues(alpha: 0.12),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.skewX(0.12),
                  child: _PressScale(
                    onPressed: _openAppSettingsDialog,
                    child: SizedBox.expand(
                      child: Center(
                        child: Icon(
                          isPause
                              ? Icons.pause_rounded
                              : Icons.settings_rounded,
                          color: Colors.cyanAccent,
                          size: 32,
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

Future<void> _openAppSettingsDialog() async {
  if (_isAppSettingsOpen.value) return;
  final navigatorContext = _appNavigatorKey.currentContext;
  if (navigatorContext == null) return;

  final matchPauseController = _matchPauseController.value;
  final helpTopic = _currentHelpTopic.value;
  if (matchPauseController != null) {
    await matchPauseController.onOpen();
  }

  // Closing the dialog without picking a pause option (tapping outside or the
  // close button) must still resume the match.
  var matchActionTaken = false;
  final trackedPauseController = matchPauseController == null
      ? null
      : MatchPauseController(
          onOpen: matchPauseController.onOpen,
          onAction: (action) {
            matchActionTaken = true;
            return matchPauseController.onAction(action);
          },
        );

  _isAppSettingsOpen.value = true;
  try {
    await showGeneralDialog<void>(
      context: navigatorContext,
      barrierDismissible: true,
      barrierLabel: 'Settings',
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
                child: AppSettingsDialog(
                  matchPauseController: trackedPauseController,
                  helpTopic: helpTopic,
                ),
              ),
            ],
          ),
        );
      },
      // Fades in like the pages, without the bounce.
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
    if (matchPauseController != null && !matchActionTaken) {
      await matchPauseController.onAction('resume');
    }
  } finally {
    _isAppSettingsOpen.value = false;
  }
}

class AppSettingsDialog extends StatefulWidget {
  final MatchPauseController? matchPauseController;
  final String? helpTopic;

  const AppSettingsDialog({
    super.key,
    this.matchPauseController,
    this.helpTopic,
  });

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

enum _SettingsTab { match, general, language, help }

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late AppLanguage _selectedUiLang;
  late AppLanguage _selectedCardLang;
  late _SettingsTab _tab;

  @override
  void initState() {
    super.initState();
    // Paused matches open on the match actions, everything else on general.
    _tab = widget.matchPauseController != null
        ? _SettingsTab.match
        : _SettingsTab.general;
    _selectedUiLang = LanguageController.instance.uiLanguage;
    _selectedCardLang = LanguageController.instance.cardLanguage;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(_selectedUiLang);
    final tabs = _availableTabs;

    final modal = BakuganModal(
      title: _tabLabel(_tab, l10n),
      icon: _tabIcon(_tab),
      width: 900,
      // The frame is slanted but the content is upright, so the frame's edges
      // sit up to ~0.06 x height away from the content at the top-left and the
      // bottom-right corners. The padding has to cover that.
      contentPadding: const EdgeInsets.fromLTRB(84, 0, 84, 36),
      // Right edge padding also positions the OK button: kept small so it sits
      // close to the corner, but enough that the slanted edge does not cut it.
      edgePadding: const EdgeInsets.fromLTRB(64, 0, 62, 0),
      insetPadding: const EdgeInsets.all(_modalInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Every tab gets the same height, so switching tabs does not resize
          // the dialog.
          SizedBox(
            height: _tabContentHeight,
            child: SingleChildScrollView(
              key: ValueKey(_tab),
              child: switch (_tab) {
                _SettingsTab.match => _buildMatchTab(),
                _SettingsTab.general => _buildGeneralTab(l10n),
                _SettingsTab.language => _buildLanguageTab(l10n),
                _SettingsTab.help => _buildHelpTab(),
              },
            ),
          ),
        ],
      ),
      actions: [
        BakuganModalActionButton(
          text: l10n.ok,
          showGrid: false,
          useGradientBorder: false,
          onPressed: () {
            LanguageController.instance.setLanguages(
              ui: _selectedUiLang,
              card: _selectedCardLang,
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );

    // The tabs hang off the slanted left edge of the frame, like the attribute
    // rail of the large Bakugan preview. They are drawn first and reach under
    // the frame, so their open side is hidden behind it. The same space is
    // left on the right so the frame stays centred, and the rail stays inside
    // the Stack so it can be tapped.
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: _modalInset,
          bottom: _modalInset,
          // Reaches past the frame's left edge, which sits after the inset.
          width: _tabRailWidth + _modalInset + _sideTabUnderlap,
          child: Transform(
            alignment: Alignment.center,
            // Same slant as the frame, so each tab meets the edge at its height.
            transform: Matrix4.skewX(-0.12),
            // Stacked one under the other from the top, like the attributes.
            child: Stack(
              children: [
                for (final (index, tab) in tabs.indexed)
                  Positioned(
                    top: _sideTabTop + index * (_sideTabHeight + 4),
                    right: 0,
                    child: _buildSideTab(tab, l10n),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _tabRailWidth),
          child: modal,
        ),
      ],
    );
  }

  static const double _tabRailWidth = 150;
  static const double _modalInset = 24;
  static const double _sideTabHeight = 86;
  static const double _sideTabTop = 28;
  // How far each tab reaches under the frame.
  static const double _sideTabUnderlap = 24;

  Widget _buildSideTab(_SettingsTab tab, AppLocalizations l10n) {
    const accentColor = Colors.cyanAccent;
    const popOutDistance = 26.0;
    final isSelected = tab == _tab;
    final borderSide = BorderSide(
      color: isSelected ? accentColor : Colors.white24,
      width: isSelected ? 2 : 1,
    );
    return GestureDetector(
      onTap: () {
        if (isSelected) return;
        _playUiConfirmSound();
        setState(() => _tab = tab);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: _sideTabUnderlap + (isSelected ? 110 + popOutDistance : 110),
        height: _sideTabHeight,
        // Keeps the icon and label centred in the part outside the frame.
        padding: const EdgeInsets.only(right: _sideTabUnderlap),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.28)
              : const Color(0xFF070C12).withValues(alpha: 0.92),
          border: Border(top: borderSide, left: borderSide, bottom: borderSide),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(15),
            bottomLeft: Radius.circular(15),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.35),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(0.12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _tabIcon(tab),
                color: isSelected ? Colors.white : Colors.white70,
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                _tabLabel(tab, l10n),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'button_font',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Saved as soon as it is picked, so closing the dialog any way keeps it.
  void _saveLanguages() {
    unawaited(
      LanguageController.instance.setLanguages(
        ui: _selectedUiLang,
        card: _selectedCardLang,
      ),
    );
  }

  // Fits the general tab, the tallest one, with the two-line description of
  // the cartoon previews; longer help topics scroll.
  static const double _tabContentHeight = 470;

  _HelpTopic? get _helpTopic {
    final topicId = widget.helpTopic;
    return topicId == null ? null : _helpTopics[topicId];
  }

  List<_SettingsTab> get _availableTabs => [
    if (widget.matchPauseController != null) _SettingsTab.match,
    _SettingsTab.general,
    _SettingsTab.language,
    if (_helpTopic != null) _SettingsTab.help,
  ];

  String _tabLabel(_SettingsTab tab, AppLocalizations l10n) {
    return switch (tab) {
      _SettingsTab.match => l10n.matchTab,
      _SettingsTab.general => l10n.generalTab,
      _SettingsTab.language => l10n.languageLabel,
      _SettingsTab.help => l10n.help,
    };
  }

  IconData _tabIcon(_SettingsTab tab) {
    return switch (tab) {
      _SettingsTab.match => Icons.pause_rounded,
      _SettingsTab.general => Icons.tune_rounded,
      _SettingsTab.language => Icons.language_rounded,
      _SettingsTab.help => Icons.help_outline_rounded,
    };
  }

  Widget _buildMatchTab() {
    final matchPauseController = widget.matchPauseController!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FramedActionButton(
          text: 'RESUME',
          icon: Icons.play_arrow_rounded,
          gradient: _gateDescriptionBorderGradients['silver']!,
          accentColor: const Color(0xFFE8EDF2),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(matchPauseController.onAction('resume'));
          },
          width: double.infinity,
          height: 64,
          textFontSize: 26,
          iconSize: 30,
        ),
        const SizedBox(height: 14),
        FramedActionButton(
          text: 'RESTART',
          icon: Icons.restart_alt_rounded,
          gradient: const [
            Color(0xFF5A2E0B),
            Color(0xFFE08A2E),
            Color(0xFFFFC27A),
            Color(0xFF3A1E06),
          ],
          accentColor: Colors.orangeAccent,
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(matchPauseController.onAction('selection'));
          },
          width: double.infinity,
          height: 64,
          textFontSize: 26,
          iconSize: 30,
        ),
        const SizedBox(height: 14),
        FramedActionButton(
          text: 'EXIT TO MENU',
          icon: Icons.home_rounded,
          gradient: _abilityDescriptionBorderGradients['red']!,
          accentColor: Colors.redAccent,
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(matchPauseController.onAction('main_menu'));
          },
          width: double.infinity,
          height: 64,
          textFontSize: 26,
          iconSize: 30,
        ),
      ],
    );
  }

  Widget _buildGeneralTab(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          icon: Icons.volume_up_rounded,
          label: l10n.volume,
          color: Colors.cyanAccent,
        ),
        const SizedBox(height: 12),
        const _AppVolumeControls(),
        const SizedBox(height: 24),
        _buildSectionLabel(
          icon: Icons.tune_rounded,
          label: l10n.automation,
          color: Colors.greenAccent,
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: AutomationController.instance,
          builder: (context, _) {
            final current = AutomationController.instance.level;
            return _buildChoiceRow(
              options: [
                for (final level in AutomationLevel.values)
                  (
                    label: level.label(_selectedUiLang),
                    isSelected: level == current,
                    onTap: () => unawaited(
                      AutomationController.instance.setLevel(level),
                    ),
                  ),
              ],
              description: current.description(_selectedUiLang),
              accentColor: Colors.greenAccent,
            );
          },
        ),
        const SizedBox(height: 24),
        _buildSectionLabel(
          icon: Icons.view_in_ar_rounded,
          label: l10n.previewStyle,
          color: Colors.pinkAccent,
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: PreviewStyleController.instance,
          builder: (context, _) {
            final current = PreviewStyleController.instance.style;
            return _buildChoiceRow(
              options: [
                for (final style in BakuganPreviewStyle.values)
                  (
                    label: style.label(_selectedUiLang),
                    isSelected: style == current,
                    onTap: () => unawaited(
                      PreviewStyleController.instance.setStyle(style),
                    ),
                  ),
              ],
              description: current.description(_selectedUiLang),
              accentColor: Colors.pinkAccent,
            );
          },
        ),
      ],
    );
  }

  Widget _buildChoiceRow({
    required List<({String label, bool isSelected, VoidCallback onTap})>
    options,
    required String description,
    required Color accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final option in options) ...[
              if (option != options.first) const SizedBox(width: 14),
              _buildChoiceOption(
                label: option.label,
                isSelected: option.isSelected,
                accentColor: accentColor,
                onTap: () {
                  _playUiConfirmSound();
                  option.onTap();
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageTab(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.uiLanguageLabel.toUpperCase(),
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final language in AppLanguage.values) ...[
              if (language != AppLanguage.values.first)
                const SizedBox(width: 14),
              _buildLanguageOption(
                language: language,
                isSelected: _selectedUiLang == language,
                accentColor: Colors.cyanAccent,
                onTap: () {
                  _playUiConfirmSound();
                  setState(() => _selectedUiLang = language);
                  _saveLanguages();
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(
          l10n.cardLanguageLabel.toUpperCase(),
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final language in AppLanguage.values) ...[
              if (language != AppLanguage.values.first)
                const SizedBox(width: 14),
              _buildLanguageOption(
                language: language,
                isSelected: _selectedCardLang == language,
                accentColor: Colors.amberAccent,
                onTap: () {
                  _playUiConfirmSound();
                  setState(() => _selectedCardLang = language);
                  _saveLanguages();
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildHelpTab() {
    final topic = _helpTopic!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          icon: Icons.help_outline_rounded,
          label: topic.title(_selectedUiLang),
          color: Colors.amberAccent,
        ),
        const SizedBox(height: 16),
        _HelpTipsList(topic: topic, language: _selectedUiLang),
      ],
    );
  }

  Widget _buildSectionLabel({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color accentColor = Colors.greenAccent,
  }) {
    return Expanded(
      child: _PressScale(
        onPressed: onTap,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white24,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.skewX(0.12),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required AppLanguage language,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: _PressScale(
        onPressed: onTap,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white24,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.skewX(0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LanguageFlag(language: language),
                  const SizedBox(width: 10),
                  Text(
                    language.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 16,
                      fontWeight: isSelected
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppVolumeControls extends StatelessWidget {
  const _AppVolumeControls();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: AppVolumeController.instance,
      builder: (context, _) {
        final controller = AppVolumeController.instance;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.12),
          child: Container(
            height: 86,
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.cyanAccent.withValues(alpha: 0.75),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.skewX(0.12),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: controller.isMuted
                        ? l10n.unmuteAudio
                        : l10n.muteAudio,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.skewX(-0.12),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withValues(alpha: 0.2),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.skewX(0.12),
                          child: _PressScale(
                            onPressed: () => unawaited(controller.toggleMute()),
                            child: SizedBox.expand(
                              child: Center(
                                child: Icon(
                                  controller.isMuted || controller.volume == 0
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.92),
                            const Color(0xFF07151B).withValues(alpha: 0.9),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 8,
                                activeTrackColor: Colors.cyanAccent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.cyanAccent,
                                overlayColor: Colors.cyanAccent.withValues(
                                  alpha: 0.16,
                                ),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 10,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 18,
                                ),
                              ),
                              child: Slider(
                                value: controller.volume,
                                onChanged: (value) =>
                                    unawaited(controller.setVolume(value)),
                              ),
                            ),
                          ),
                          Text(
                            '${(controller.volume * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
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
        );
      },
    );
  }
}
