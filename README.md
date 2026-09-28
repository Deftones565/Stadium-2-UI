# Pokemon Stadium 2 Battle UI

Pokemon Stadium 2's battle UI for the Gen 1 and Gen 2 games, recreated in
Lua. No ROM is needed and no game data is included: every texture and both
fonts are painted in code, following the look of the original.

- Status panels: name, level, status, gender, HP bar and numbers, trainer
  tag and party balls
- Stadium's message box
- Command bar: BATTLE, POKeMON, RUN, plus PACK (not in Stadium 2)
- Move diamond with type colours and PP; the move info card (power,
  accuracy and, in Gen 2, the move's description)
- Switch cards for up to six Pokemon (Stadium teams have three)
- Stadium's YES/NO window for the game's yes/no questions

It draws over the Game Boy battle, or over STADIUM2_IMPORTER's 3D battle.
The portrait box beside each status panel shows the Pokemon's front sprite
(coloured as the battle colours it) in sprite battles, and Stadium's live
3D portrait in the importer's 3D battle (its models and camera data come
from the importer's ROM import). If the importer's own STADIUM UI option is on, this mod stands
aside; turn that option off to use this one.

The layout fits any window or screen: it scales to the largest size where
everything fits, pins the status panels to the screen edges, centres the
menus, and moves the opponent's panel out of the way of menus and message
boxes (leaving out its portrait and balls, or for a moment the whole panel,
only when there is no room), so nothing overlaps or leaves the screen.

In the game's own (unmodded) battle scene the mod also moves the Game Boy
battlefield: the Stadium menus keep the top, a two-line message box sits at
the bottom, and the battlefield with both Pokemon is drawn in the space
between, as large as fits, so the UI never covers a Pokemon. The host's
WIDE battle layout and the "world" battle background are left as they are.

## Options

| Option | What it does |
|---|---|
| STADIUM UI | The Stadium battle UI on or off (on by default). |
| MENU CONTROLS | With a controller the menus use Stadium 2's controls (no cursor, A BATTLE, B POKeMON, START RUN, R PACK, C buttons on the right stick, hold the D-pad for a move's info, LB cancels). On keyboard, `CURSOR` keeps a moving cursor (hold R for info) and `STADIUM` uses the controller scheme (C = I/J/K/L). |
| UI DETAIL | `HD` smooths the pixel art and font for big screens; `N64 PIXELS` shows crisp pixels. |
| CONTROLLER ICONS | `AUTO` follows the controller you last used; or pick `XBOX`, `PLAYSTATION`, `AYN THOR`, `STEAM DECK` or `NATIVE N64`. |
| THOR INPUT MODE | For the AYN Thor: match its controller style so A/B and X/Y prompts line up. |

## How it works

The mod only uses the host's public mod hooks; no engine function is
patched. `render.hud` draws the UI over the finished frame;
`battle.status_hud_visible`, `battle.bottom_ui_visible` and
`screen.render_visible` hide the host's own HUD, text box, party menu and
YES/NO while the Stadium UI stands in for them; `input.step`,
`input.pointer` and (from the first Stadium menu) `input.gamepad` drive the
menus through the host's own menu state.

The layout, colours and menu behaviour come from the research in
STADIUM2_IMPORTER (`docs/luna/research/stadium2-battle-ui.md`).

## Tests

From the gen1recomp repository root:

    for t in mods/STADIUM2_UI/tests/*_test.lua; do luajit "$t"; done
