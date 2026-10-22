part of '../../main.dart';

// Topic id of the screen currently on top of the navigator, or null when that
// screen has no help (splash, dialogs).
final ValueNotifier<String?> _currentHelpTopic = ValueNotifier<String?>(null);

String? _helpTopicForPage(Widget page) {
  if (page is MainMenuScreen) return 'main_menu';
  if (page is BattleModeScreen) return 'battle_mode';
  if (page is CharacterSelectScreen) return 'character_select';
  if (page is BakuganSelectScreen) return 'bakugan_select';
  if (page is ScoreboardScreen) return 'scoreboard';
  if (page is BattleArenaScreen) return 'arena';
  if (page is InventoryScreen) return 'inventory';
  if (page is BakuganInventoryCarouselScreen) return 'inventory_bakugan';
  if (page is InventoryCardsScreen) return 'inventory_cards';
  if (page is LeaderboardScreen) return 'leaderboard';
  if (page is MatchHistoryScreen) return 'history';
  return null;
}

class _HelpTopicObserver extends NavigatorObserver {
  // Dialogs and menus are popup routes; they must not replace the topic of the
  // screen they were opened from.
  void _set(Route<dynamic>? route) {
    final name = route?.settings.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentHelpTopic.value = name;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) return;
    _set(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PopupRoute) return;
    _set(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) return;
    _set(previousRoute);
  }
}

class _HelpTip {
  final String es;
  final String en;

  const _HelpTip(this.es, this.en);

  String of(AppLanguage language) => language == AppLanguage.es ? es : en;
}

class _HelpTopic {
  final String titleEs;
  final String titleEn;
  final List<_HelpTip> tips;

  const _HelpTopic({
    required this.titleEs,
    required this.titleEn,
    required this.tips,
  });

  String title(AppLanguage language) =>
      language == AppLanguage.es ? titleEs : titleEn;
}

const Map<String, _HelpTopic> _helpTopics = {
  'main_menu': _HelpTopic(
    titleEs: 'MENÚ PRINCIPAL',
    titleEn: 'MAIN MENU',
    tips: [
      _HelpTip(
        'BATALLA empieza una partida. INVENTARIO es donde marcas qué Bakugan tienes.',
        'BATTLE starts a match. INVENTORY is where you mark which Bakugan you own.',
      ),
      _HelpTip(
        'SAVEGAME exporta toda la app (jugadores, inventario, historial, clasificación) a un archivo JSON, o la restaura desde uno.',
        'SAVEGAME exports the whole app (players, inventory, history, leaderboard) to a JSON file, or restores it from one.',
      ),
      _HelpTip(
        'El botón de ajustes de arriba a la derecha cambia el volumen y los idiomas, y tiene AYUDA con las instrucciones de cada pantalla. El idioma de la interfaz y el de las cartas son independientes.',
        'The settings button at the top right changes volume and languages, and has HELP with the instructions of each screen. The interface language and the card text language are independent.',
      ),
      _HelpTip(
        'AUTOMATIZACIÓN, en los ajustes, decide cuánto resuelve la app. MANUAL: no suma bonus ni aplica efectos y los botones manuales están siempre visibles. ASISTIDO: aplica lo que conoce y deja un respaldo manual a la vista. AUTO: lo hace todo sola, sin botones manuales. Se puede cambiar en mitad de una partida.',
        'AUTOMATION, in the settings, decides how much the app resolves. MANUAL: it adds no bonuses and applies no effects, and the manual buttons are always visible. ASSISTED: it applies what it knows and keeps a manual fallback in view. AUTO: it does it all by itself, with no manual buttons. You can change it in the middle of a match.',
      ),
    ],
  ),
  'battle_mode': _HelpTopic(
    titleEs: 'MODO DE BATALLA',
    titleEn: 'BATTLE MODE',
    tips: [
      _HelpTip(
        'BATTLE ROYALE es para 2 a 4 jugadores, cada uno por su cuenta. MODO EQUIPOS es para cuatro jugadores en dos equipos de dos.',
        'BATTLE ROYALE is for 2 to 4 players, each on their own. TEAM BATTLE is for four players in two teams of two.',
      ),
    ],
  ),
  'character_select': _HelpTopic(
    titleEs: 'SELECCIÓN DE JUGADORES',
    titleEn: 'PLAYER SELECTION',
    tips: [
      _HelpTip(
        'REGISTRAR guarda al jugador para próximas partidas. Solo los jugadores registrados puntúan en la clasificación y el Elo.',
        'REGISTER saves the player for future matches. Only registered players score in the leaderboard and Elo.',
      ),
      _HelpTip(
        'INVITAR crea un jugador temporal que solo existe en esta partida.',
        'INVITE creates a temporary player that only exists for this match.',
      ),
    ],
  ),
  'bakugan_select': _HelpTopic(
    titleEs: 'SELECCIÓN DE BAKUGAN',
    titleEn: 'BAKUGAN SELECTION',
    tips: [
      _HelpTip(
        'Cada jugador elige 3 Bakugan. Toca el panel de un jugador para cambiar de jugador, y toca un Bakugan ya elegido para quitarlo.',
        'Each player picks 3 Bakugan. Tap a player panel to switch player, and tap an already picked Bakugan to remove it.',
      ),
      _HelpTip(
        'Con el modo colección activado solo salen los Bakugan que tienes en el inventario (los que tienen G distinto de 0). Desactívalo para ver todos.',
        'With collection mode on, only the Bakugan in your inventory are shown (the ones with G above 0). Turn it off to see them all.',
      ),
      _HelpTip(
        'Puedes filtrar por atributo y ordenar por G-Power con las pestañas de arriba.',
        'You can filter by attribute and sort by G-Power with the tabs at the top.',
      ),
    ],
  ),
  'scoreboard': _HelpTopic(
    titleEs: 'MARCADOR',
    titleEn: 'SCOREBOARD',
    tips: [
      _HelpTip(
        'Los puntos se ganan al ganar una batalla. Si hay que corregirlos, usa el modo de edición (el lápiz).',
        'Points are won by winning battles. To fix them, use the edit mode (the pencil).',
      ),
      _HelpTip(
        'Debajo de cada Bakugan se lee su estado: UNUSED (en la pila), STAND (en juego), USED o DOOMED (fuera del juego). Al tocarlo pasa de UNUSED a STAND, a USED y vuelve a UNUSED.',
        'Under each Bakugan you can read its state: UNUSED (in the pile), STAND (in play), USED or DOOMED (out of the game). Tapping it goes from UNUSED to STAND, to USED and back to UNUSED.',
      ),
      _HelpTip(
        'BATALLA: elige un Bakugan en STAND de cada bando y pulsa FIGHT! para ir a la arena. BACK cancela.',
        'BATTLE: pick one Bakugan in STAND from each side and press FIGHT! to go to the arena. BACK cancels.',
      ),
      _HelpTip(
        'Cuando un jugador tiene sus 3 Bakugan en STAND aparece STAY como cuarto recuadro: devuelve el más antiguo a UNUSED y suma un punto.',
        'When a player has all 3 Bakugan in STAND, STAY appears as a fourth tile: it sends the oldest one back to UNUSED and adds a point.',
      ),
      _HelpTip(
        'Las cartas boca abajo junto al perfil son de habilidad: tócalas para presentar una y búscala por nombre. Mantén pulsada una presentada para darle la vuelta: se atenúa y su efecto se anula. Las habilidades globales salen también en el centro.',
        'The face-down cards by the profile are ability cards: tap one to present a card and search it by name. Long-press a presented one to flip it: it dims and its effect is cancelled. Global abilities also show in the centre.',
      ),
      _HelpTip(
        'El + del centro (Manual y Asistido) añade una carta de puerta que sigue en efecto, como Forest Fire, con su bonus y los atributos que afecta. Tócala para leerla y quitarla.',
        'The + in the centre (Manual and Assisted) adds a Gate card that stays in effect, like Forest Fire, with its bonus and the attributes it affects. Tap it to read it and remove it.',
      ),
      _HelpTip(
        'Modo de edición (el lápiz, en Manual y Asistido): los jugadores se amplían, cada Bakugan tiene un − para mandarlo a DOOMED (y un + para devolverlo) y los puntos tienen + y −. DONE sale del modo.',
        'Edit mode (the pencil, in Manual and Assisted): the players expand, each Bakugan has a − to send it to DOOMED (and a + to bring it back) and the points have + and −. DONE leaves the mode.',
      ),
      _HelpTip(
        'Con 3 puntos aparece WIN? junto a la puntuación para confirmar la victoria (en Auto se declara sola). En la pantalla de victoria, KEEP BRAWLING la retira, restaura la clasificación y deja la victoria automática apagada el resto de la partida.',
        'With 3 points, WIN? appears next to the score to confirm the win (in Auto it is declared by itself). On the victory screen, KEEP BRAWLING takes it back, restores the leaderboard and keeps the automatic win off for the rest of the match.',
      ),
    ],
  ),
  'arena': _HelpTopic(
    titleEs: 'ARENA',
    titleEn: 'ARENA',
    tips: [
      _HelpTip(
        'Toca la carta boca abajo del centro para elegir la carta de puerta que se revela. Después, tócala para terminar el combate: en Asistido y Auto gana el Bakugan con más G-Power (salvo que la carta diga otra cosa); en Manual sale una ventana para elegir ganador o empate.',
        'Tap the face-down card in the centre to choose the Gate card that is revealed. Then tap it to end the fight: in Assisted and Auto the Bakugan with the most G-Power wins (unless the card says otherwise); in Manual a window asks you to pick a winner or a tie.',
      ),
      _HelpTip(
        'Tras el resultado, CHANGE RESULT (Manual y Asistido) permite cambiarlo antes de salir con OK.',
        'After the result, CHANGE RESULT (Manual and Assisted) lets you change it before leaving with OK.',
      ),
      _HelpTip(
        'El + junto al G-Power de cada Bakugan (Manual y Asistido) abre una ventana para sumar o restar G-Power y, con el desplegable ATTRIBUTE, cambiar su atributo. APPLY aplica las dos cosas; RESET quita el ajuste manual.',
        "The + beside each Bakugan's G-Power (Manual and Assisted) opens a window to add or remove G-Power and, with the ATTRIBUTE dropdown, change its attribute. APPLY applies both; RESET removes the manual adjustment.",
      ),
      _HelpTip(
        'En Manual la app no suma bonus ni aplica efectos de cartas: el G-Power es el impreso más lo que pongas tú. En Asistido y Auto sí los aplica (los efectos que conoce).',
        'In Manual the app adds no bonuses and applies no card effects: the G-Power is the printed one plus what you set. In Assisted and Auto it applies them (the effects it knows).',
      ),
      _HelpTip(
        'A los lados puedes presentar cartas de habilidad durante el combate. Las que aparecen atenuadas fueron anuladas en el marcador.',
        'On the sides you can present ability cards during the fight. Dimmed ones were cancelled on the scoreboard.',
      ),
      _HelpTip(
        'La flecha de arriba a la izquierda vuelve al marcador sin terminar el combate.',
        'The arrow at the top left returns to the scoreboard without finishing the fight.',
      ),
    ],
  ),
  'inventory': _HelpTopic(
    titleEs: 'INVENTARIO',
    titleEn: 'INVENTORY',
    tips: [
      _HelpTip(
        'BAKUGAN es donde indicas cuáles tienes, para que solo esos salgan en la selección. CARDS sirve para consultar todas las cartas de la app.',
        'BAKUGAN is where you set which ones you own, so only those show up in selection. CARDS lets you browse every card in the app.',
      ),
    ],
  ),
  'inventory_bakugan': _HelpTopic(
    titleEs: 'INVENTARIO · BAKUGAN',
    titleEn: 'INVENTORY · BAKUGAN',
    tips: [
      _HelpTip(
        'Toca un atributo para previsualizarlo. La pestaña EDIT fija el G-Power del atributo seleccionado: con 0 (o vacío) no cuenta como parte de la colección.',
        'Tap an attribute to preview it. The EDIT tab sets the G-Power of the selected attribute: with 0 (or empty) it does not count as part of the collection.',
      ),
      _HelpTip(
        'Las pestañas de arriba filtran por atributo y ordenan por G-Power (el orden necesita un atributo elegido). COLLECTION MODE alterna entre ver solo los que tienes o todos.',
        'The tabs at the top filter by attribute and sort by G-Power (sorting needs an attribute selected). COLLECTION MODE switches between showing only the ones you own or all of them.',
      ),
      _HelpTip(
        'RESET ALL, junto al botón de ajustes, pone a cero el G-Power de toda tu colección (pide confirmación).',
        'RESET ALL, next to the settings button, sets the G-Power of your whole collection to zero (it asks for confirmation).',
      ),
    ],
  ),
  'inventory_cards': _HelpTopic(
    titleEs: 'INVENTARIO · CARTAS',
    titleEn: 'INVENTORY · CARDS',
    tips: [
      _HelpTip(
        'Desliza o toca una carta lateral para centrarla. Los filtros de clase de arriba ocultan las demás.',
        'Swipe or tap a side card to centre it. The class filters at the top hide the others.',
      ),
      _HelpTip(
        'PERSISTENT, junto al buscador, muestra solo las cartas que siguen en efecto mientras están en una pila de usadas. Se combina con el buscador y con el color.',
        'PERSISTENT, next to the search, shows only the cards that stay in effect while they are in a used pile. It combines with the search and the colour.',
      ),
    ],
  ),
  'leaderboard': _HelpTopic(
    titleEs: 'CLASIFICACIÓN',
    titleEn: 'LEADERBOARD',
    tips: [
      _HelpTip(
        'El Elo se calcula por temporadas, y solo con jugadores registrados. Cada jugador debe pulsar INICIAR TEMPORADA para entrar en ella.',
        'Elo is calculated per season, and only for registered players. Each player must press START SEASON to join it.',
      ),
      _HelpTip(
        'PAUSAR ELO congela la clasificación para todos: las partidas no la modifican hasta que reanudes.',
        'PAUSE ELO freezes the leaderboard for everyone: matches do not change it until you resume.',
      ),
      _HelpTip(
        'TERMINAR TEMPORADA cierra el ranking actual y lo archiva. Las temporadas archivadas se pueden consultar.',
        'END SEASON closes the current ranking and archives it. Archived seasons can still be viewed.',
      ),
    ],
  ),
  'history': _HelpTopic(
    titleEs: 'HISTORIAL',
    titleEn: 'HISTORY',
    tips: [
      _HelpTip(
        'Aquí aparecen las partidas terminadas, con su modo (batalla o equipos), jugadores y resultado.',
        'Finished matches are listed here, with their mode (battle or team), players and result.',
      ),
    ],
  ),
};

Future<void> _openHelpDialog(String topicId) async {
  final topic = _helpTopics[topicId];
  final navigatorContext = _appNavigatorKey.currentContext;
  if (topic == null || navigatorContext == null) return;

  _isAppSettingsOpen.value = true;
  try {
    await showGeneralDialog<void>(
      context: navigatorContext,
      barrierDismissible: true,
      barrierLabel: 'Help',
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
              Center(child: _HelpDialog(topic: topic)),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curvedAnimation, child: child),
        );
      },
    );
  } finally {
    _isAppSettingsOpen.value = false;
  }
}

class _HelpDialog extends StatelessWidget {
  final _HelpTopic topic;

  const _HelpDialog({required this.topic});

  @override
  Widget build(BuildContext context) {
    final language = LanguageController.instance.uiLanguage;

    return BakuganModal(
      title: topic.title(language),
      icon: Icons.help_outline_rounded,
      accentColor: Colors.amberAccent,
      width: 900,
      // The modal is skewed, so content needs extra side padding or its
      // corners get clipped by the slanted edges.
      contentPadding: const EdgeInsets.fromLTRB(80, 0, 80, 36),
      edgePadding: const EdgeInsets.symmetric(horizontal: 40),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final tip in topic.tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 12),
                        child: Icon(
                          Icons.arrow_right_rounded,
                          color: Colors.amberAccent,
                          size: 22,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          tip.of(language),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
