# Shinty (working title)

A 3D shinty match game built in Godot 4.7. Pick Kingussie or Aberdour, pick
their ground to play at, and play a full 12-a-side match against the computer.

## Run it

1. Install Godot 4.7 or newer (standard build, not .NET) from https://godotengine.org.
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** (Run).

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | WASD / arrow keys | Left stick |
| Sprint | Shift | RB |
| Hit (hold for more power), or tackle the ball carrier | Space | X / Square |
| Pass to the team-mate you're facing | E | A / Cross |
| Switch player | Q | LB |
| Pause (M to quit while paused) | Esc | Start |

Shots aimed roughly at the hail get a little aim assist. The ball can be in the
air: a lofted hit sails over players, and the keeper can reach higher than
outfield players.

## Squads and ratings

Squads live in `data/teams.json`. The players are placeholders ("Player 1" to
"Player 12") with made-up ratings. To use real squads, edit the names and
numbers; keep one player per position code:

`GK, FB, LHB, CHB, RHB, LM, RM, LHF, CHF, RHF, CF, FF`

Players listed after the first at a position are treated as substitutes (not
used in matches yet). Ratings run 1 to 99: `pace, control, passing, shooting,
tackling, keeping, stamina`. Overall ratings are calculated from these,
weighted by position (see `scripts/team_data.gd`). To add a club, add another
entry to `teams` with an `id`, `name`, `short` and `colors`.

## How it plays

- 12-a-side, 150 x 75 yard pitch, hails 12 ft wide and 10 ft high.
- Matches start (and restart after every hail) with a throw-up.
- Ball over the sideline: a shy to the other side. Over the byline: a hit-out,
  or a corner if a defender put it there.
- Ratings matter: pace sets speed, control decides whether you trap a fast ball
  or keep it in a tackle, passing and shooting set accuracy, keeping sets the
  keeper's reach and save chance.
- Difficulty changes the computer's reaction time and a small skill modifier.

## Project layout

- `scenes/main_menu.tscn`, `scripts/main_menu.gd`: team and match setup.
- `scenes/match.tscn`, `scripts/match.gd`: the match rules, ball physics and AI.
  The simulation runs on a flat pitch in yards; nothing in it depends on 3D.
- `scripts/team_ai.gd`: what computer players do off the ball: support
  angles, runs in behind, overlaps, coming short, marking and cover.
- `scripts/match_view.gd`: builds and animates the 3D players, ball, hails and
  broadcast camera from the match state, using the models in `models/`.
- `pitch/`: the grounds (Aberdour and Kingussie's The Dell) with their
  scenery, sky and lighting; each ground's layout is in `pitch/venues/`. See
  `docs/pitch.md`. The match uses it in yards (`units_per_yard = 1`) with its
  own placeholder goals turned off, at the ground picked in the menu.
- `scripts/hud.gd`: scoreboard, power bar and messages on top of the 3D view.
- `scripts/game.gd`: autoload with menu choices and control bindings.
- `scripts/team_data.gd`: loads squads and calculates overall ratings.
- `tests/sim_test.gd`: plays six computer-vs-computer matches headless.
  Run: `godot --headless --path . -s tests/sim_test.gd`
- `tests/ai_stats.gd`: plays ten matches and prints pass, shot and restart
  numbers, for tuning the team AI.
- `tests/play_test.gd`: drives the real game with simulated key presses and
  saves screenshots (needs a display).
- `tests/menu_test.gd`: clicks through the menu dropdowns and Play button.
- `models/`: 3D player, ball and hail models plus the hitting and ball-flight
  physics (`ShintyPlayerModel`, `ShintyBallModel`, `ShintyHailModel`,
  `ShintyStrike`, `ShintyBallPhysics`, `ShintyMatchAdapter`). See
  `docs/models.md`.
- `demo/showcase.tscn`: model showcase (squads lined up, a forward shooting,
  a keeper diving). Open it and press F6. Keys 1 to 4 change camera, Space
  hits, L toggles lofted hits.
- `tests/model_test.gd`: model and physics checks.
  Run: `godot --headless --path . -s tests/model_test.gd`
- `preview/preview.tscn`: orbit-camera preview of the pitch on its own. Open
  it and press F6. Drag to orbit, scroll to zoom, 1 to 6 for set views, L for
  lighting, V to switch ground.
- `tests/render_views.gd`: renders the pitch views into `renders/`.
  Run: `xvfb-run godot --path . --rendering-method gl_compatibility -s tests/render_views.gd`
- `docs/`: notes for the models and pitch, and screenshots.

## Building for Steam

1. In Godot: **Editor > Manage Export Templates > Download and Install**.
2. **Project > Export**, add Windows Desktop, Linux and macOS presets. Under
   **Resources**, set "Filters to export non-resource files" to `*.json` so
   the squad file is included.
3. Export to an `export/` folder and upload the builds through Steamworks
   (needs a Steamworks partner account and the Steam Direct app fee).
   Achievements, overlay and online play would use the GodotSteam plugin later.
