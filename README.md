# Shinty (working title)

A 3D shinty match game built in Godot 4.7. Pick Kingussie or Aberdour and play
a full 12-a-side match against the computer.

## Run it

1. Install Godot 4.7 or newer (standard build, not .NET) from https://godotengine.org.
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** (Run).

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | WASD / arrow keys | Left stick |
| Sprint | Shift | RB |
| Hit (hold for more power, release to swing), or poke at the carrier's ball | Space | X / Square |
| Pass to the team-mate you're facing | E | A / Cross |
| Block (back of the stick over their ball) | F | Y / Triangle |
| Cleek (stick up under their swing) | C | B / Circle |
| Shoulder barge | R | Left stick click |
| Switch player | Q | LB |
| Pause (M to quit while paused) | Esc | Start |

Shots aimed roughly at the goal get a little aim assist. The ball can be in the
air: a lofted hit sails over players, and the keeper can reach higher than
outfield players.

The hit meter works like a golf game's: it fills to full power, then carries on
into a red overswing. Overswinging adds no power, only more chance of a
miss-hit or a hit that bends. You can swing before the ball reaches you to hit
it first time; if it isn't there when the caman comes through, that's fresh air.

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

- 12-a-side, 150 x 75 yard pitch, goals 12 ft wide and 10 ft high.
- Matches start (and restart after every goal) with a throw-up.
- Ball over the sideline: a shy to the other side. The taker tosses the ball
  straight up an arm's length in front and, as it drops, brings the caman over
  their head with both hands like a hammer and strikes it with the back of the
  stick. They get three attempts at a clean strike; miss all three and the shy
  goes to the other side. Over the byline: a hit-out, or a corner if a
  defender put it there.
- Players have weight (`scripts/player_physics.gd`). They accelerate like
  footballers (quick first steps, a slower build to top speed), take a stride
  or two to stop, and turn wider the faster they run. Bodies collide like ice
  hockey: heavier, faster players knock others off balance, and a hard enough
  hit on the ball carrier knocks the ball loose.
- Every player's caman is tracked. It reaches out for a loose ball, pokes at an
  opponent's ball hockey-style, and only touches the ball where the stick head
  actually gets to it. A ball can also hit a player's body and deflect.
- Hits are swings, not instant: the caman takes time to come through, so a
  carrier can be tackled mid-swing. How cleanly it meets the ball decides the
  hit, golf-style: the face and swing path set the direction and any curve,
  and a thin, fat, heel or toe contact is a miss-hit. Better players, lighter
  swings and standing still mean cleaner hits.
- Four ways to stop an opponent's swing (`scripts/swing_counters.gd`):
  swing at their ball too (get there first and it's yours, arrive late and
  it's theirs, arrive together and the camans clash and the ball goes
  anywhere); shoulder barge them (legal, but barge someone in the back and
  it's a free hit the other way if the referee sees it); block by getting the
  back of your stick over the ball (block too late and you get hit); or cleek
  by raising your stick under their swing so it glances off. The computer
  players read each swing once and pick a counter from how close they are
  and how long until it lands.
- Keepers reach for shots with stick, hands and body and dive for ones going
  wide of them. A save smothers the ball, which drops at the keeper's feet.
- Ratings matter: pace sets speed, control decides whether you trap a fast ball
  or keep it in a tackle, passing and shooting set accuracy, keeping sets the
  keeper's reach and save chance.
- Difficulty changes the computer's reaction time and a small skill modifier.

## Project layout

- `scenes/main_menu.tscn`, `scripts/main_menu.gd`: team and match setup.
- `scenes/match.tscn`, `scripts/match.gd`: the match rules, ball physics and AI.
  The simulation runs on a flat pitch in yards; nothing in it depends on 3D.
- `scripts/player_physics.gd`: running, body contact, caman reach and keeper
  dives. The AI and controls set where a player wants to go (`desired`); this
  file moves them there.
- `scripts/match_view.gd`: builds and animates the 3D players, ball, goals and
  broadcast camera from the match state, using the models in `models/`.
- `pitch/`: the Aberdour pitch, scenery, sky and lighting (from the separate
  shinty-pitch project; see `docs/pitch.md`). The match uses it in yards
  (`units_per_yard = 1`) with its own placeholder goals turned off.
- `scripts/hud.gd`: scoreboard, power bar and messages on top of the 3D view.
- `scripts/game.gd`: autoload with menu choices and control bindings.
- `scripts/team_data.gd`: loads squads and calculates overall ratings.
- `tests/sim_test.gd`: plays six computer-vs-computer matches headless.
  Run: `godot --headless --path . -s tests/sim_test.gd`
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
  it and press F6. Drag to orbit, scroll to zoom, 1 to 5 for set views, L for
  lighting.
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
