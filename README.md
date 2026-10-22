<div align="center">

<img src="assets/images/logo.png" alt="Bakugan Companion logo" width="230">


<img src="assets/readme_assets/battle-without-the-math.png"
     alt="battle-without-the-math"
     style="max-width: 100%; height: auto;" 
     width="800" />
     
<p>A fan-made companion app for real-life Bakugan players and game Masters, heavily inspired by the game.</p>

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-111827)
![Status](https://img.shields.io/badge/status-in%20development-F59E0B)

</div>

<br>

<p align="center">
  <img src="assets/readme_assets/what-is-bakugan-companion.png" width="800" style="max-width: 100%; height: auto;" alt="Bakugan Companion overview" />
</p>

Bakugan Companion is a tool for players and Game Masters who play Bakugan
in real life. It combines a collection tracker with a complete match and
battle assistant, keeping the calculations and match state under control
so everyone can focus on the game.

<p align="center">
<img width="5120" height="2880" alt="home" src="https://github.com/user-attachments/assets/4bb85829-5562-4071-901b-c05de4797c9b" />
</p>

<img src="assets/readme_assets/track-your-collection.png" alt="Track yout collection" width="700"/>

Keep track of the Bakugan and cards in your physical collection.
Browse them by attribute, type, and variant.

<p align="center">
  <img width="5120" height="2880" alt="Screenshot 2026-10-19 at 22 49 56" src="https://github.com/user-attachments/assets/e6035582-98ab-43af-8e94-a7486910acda" />
</p>

<img src="assets/readme_assets/set-up-your-match.png" alt="Set-up your match" width="700"/>

Prepare a complete match before playing: choose the format, players,
teams, and Bakugan taking part in the battle.

<p align="center">
  <img width="5120" height="2880" alt="Screenshot 2026-10-19 at 22 55 56" src="https://github.com/user-attachments/assets/c026cece-f30e-4eeb-a0d8-2636d9bb91de" />
  <img width="5120" height="2880" alt="Screenshot 2026-10-19 at 23 04 52" src="https://github.com/user-attachments/assets/bd15f7d7-c21c-4a3e-90d1-d9f61f3f8634" />
</p>

<img src="assets/readme_assets/battles-fully-automated.png" alt="Battles fully automated" width="700"/>

Run 1 vs 1 and team battles without reaching for a calculator. The app
tracks the battle state and handles power changes, bonuses, abilities,
and swaps as the action unfolds. It also has a music playlist with all the original game soundtrack.

<p align="center">
<img width="5120" height="2880" alt="Screenshot 2026-10-19 at 23 53 17" src="https://github.com/user-attachments/assets/006b1fb7-b4b4-495a-91f8-73618fbed668" />
<img width="5120" height="2880" alt="Screenshot 2026-10-19 at 23 30 07" src="https://github.com/user-attachments/assets/bc9424b0-81fe-4c7f-ae60-2a0f5ae30fdc" />
<img width="5120" height="2880" alt="Screenshot 2026-10-19 at 23 33 31" src="https://github.com/user-attachments/assets/a8dd2a4d-2dfe-4a48-8eac-a3ea4dea3329" />
</p>

### You decide how much the app does

Pick an automation level in the settings, even in the middle of a match:

- **Manual**: the app adds no bonuses and applies no effects. The manual tools
  are always visible, and you set G-Power, results and the winner yourself.
- **Assisted**: the app adds the bonuses and applies the effects it knows,
  with a manual fallback always in view.
- **Auto**: the app takes care of bonuses and the effects it knows, with no
  manual buttons in the way.

Manual tools include adjusting a Bakugan's G-Power or attribute, choosing or
changing the result of a battle, an edit mode for the piles and the points,
and a WIN? button to confirm the match. Every screen has a **HELP** button in
the settings menu.

<img src="assets/readme_assets/seasons-and-elo.png" alt="Seasons and elo" width="700"/>

Organize your games into seasons and follow player progression with an
ELO rating system.

<p align="center">
  <img width="5120" height="2880" alt="Screenshot 2026-10-19 at 23 54 32" src="https://github.com/user-attachments/assets/4540cc1c-6325-4259-ae18-ebd56adab891" />
</p>


<img src="assets/readme_assets/match-history.png" alt="Match history" width="700"/>

Review previous matches, results, players, and battle details so every
session becomes part of your play history.

<p align="center">
  <img width="5120" height="2880" alt="Screenshot 2026-10-19 at 23 54 02" src="https://github.com/user-attachments/assets/65dffb87-e02e-4f86-9843-2874f8585da1" />
</p>


<img src="assets/readme_assets/savegame-system.png" alt="Savegame system" width="700"/>


Back up and restore saved matches so tournament and campaign data stays
safe across devices or installations.


<img src="assets/readme_assets/credits.png" alt="Credits" width="700"/>

3D Models thanks to MrZangestsu and sprites thanks to Jeppa <3.
Built with Flutter and made for the Bakugan community.

## Download

Builds for Windows, macOS and Linux are published in
[Releases](../../releases). Beta builds are marked as pre-releases.

- **Windows**: unzip `bakupal-windows-x64.zip` and run the `.exe`.
- **macOS**: unzip `bakupal-macos.zip`. The app is not signed yet, so the first
  time use right click, Open.
- **Linux**: extract `bakupal-linux-x64.tar.gz` and run the executable inside.

## Do you want to build it yourself?

### Requirements

- Flutter SDK 3.x or newer
- A supported Flutter development environment

### Run locally

```bash
flutter pub get
flutter run
```

## Project status

Bakugan Companion is an evolving project. New game modes, more customizability, more cards effects and bakugan are in the way.

Known gaps in the beta:

- Some card effects are not automated yet. Use the manual tools (or Manual
  mode) to resolve them by hand.
- Many 2D images of the Bakugan in monster form are still missing; the battle
  screen shows the 3D model when there is none.

Check releases for more updates.
