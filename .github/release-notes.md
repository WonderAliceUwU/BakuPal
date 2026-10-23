# BakuPal

A fan-made companion app for real-life Bakugan players and Game Masters: a
collection tracker plus a match and battle assistant, so everyone can focus on
the game instead of the maths.

## What you get

- **Collection**: mark the Bakugan you own and set their G-Power; browse every
  card by class, text and persistent effects.
- **Matches**: Battle Royale (2 to 4 players) and team battles, with a
  scoreboard, an arena for each fight, global gate effects and ability cards.
- **Automation levels**: *Manual*, *Assisted* or *Auto*, switchable in the middle
  of a match. Manual tools let you adjust G-Power and attributes, choose or
  change a battle result, edit the piles and the points, and confirm the win.
- **Seasons and Elo**, **match history** and a **savegame** backup.
- A **HELP** button on every screen.

## New in beta 2

- **Much smaller download**: card images and 3D textures are now WebP, and
  unused design files are no longer bundled (assets went from about 2.2 GB to
  under 500 MB).
- **Cartoon previews**: a setting to show the Bakugan as drawn anime balls
  instead of 3D models in the small previews (and in battle when there is no
  monster image).
- **Settings with tabs**: General, Language, Help and, while paused, Match.
- Battle monster images are framed one by one and face the opponent on both
  sides; more polished previews and history, and no more bouncy transitions.

## Install

- **Windows**: unzip `bakupal-windows-x64.zip` and run the `.exe`.
- **macOS**: unzip `bakupal-macos.zip`. The app is not signed yet: the first
  time, right click, Open.
- **Linux**: extract `bakupal-linux-x64.tar.gz` and run the executable inside.
  If that file is not attached to this release, the Linux build is not ready yet.

## Beta: what is still missing

This is a beta, so expect rough edges:

- **Card effects**: some card effects are not automated yet. In Assisted and
  Auto the app applies the ones it knows; for the rest, use the manual tools
  (or Manual mode) and resolve them by hand.
- **Bakugan images**: many 2D images of the Bakugan in monster form are still
  missing. Where there is none, the battle screen shows the 3D model instead.
- Bugs are expected. Please report anything odd as an issue.
