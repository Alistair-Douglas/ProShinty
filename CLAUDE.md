# ProShinty: notes for working on the code

A 3D shinty match game in Godot 4.7 (Forward+, GDScript). Everything you see
is built in code: players, camans, balls, hails, pitches, crowds. README.md
covers how to play and the project layout; docs/rules.md the rules the
referee enforces; docs/models.md and docs/pitch.md the models and grounds.
Every script opens with a `##` comment saying what it does: read that first,
then only the functions you need. The big files are match.gd (~2,600 lines),
shinty_player.gd (~1,700), shinty_pitch.gd (~1,300) and main_menu.gd (~850).

## Where things live

| Area | Files |
| --- | --- |
| Match rules, ball, restarts, human controls, AI on the ball | scripts/match.gd |
| Off-ball positioning and runs | scripts/team_ai.gd |
| Bodies and camans moving, contact | scripts/player_physics.gd, scripts/swing_counters.gd, models/shinty_strike.gd, models/shinty_ball_physics.gd |
| Referee and fouls (watches `match.events`) | scripts/referee.gd |
| Subs, fatigue, injuries | scripts/substitutions.gd, scripts/subs_menu.gd, scripts/subs_bench.gd |
| Stats (also reads `match.events`) | scripts/match_stats.gd, scripts/stats_panel.gd |
| 3D drawing of the match | scripts/match_view.gd (sim yards to world metres via models/shinty_match_adapter.gd) |
| Hit feel (hit-stop, shake) | scripts/match_feel.gd |
| Weather | scripts/weather.gd, pitch/rain.gd |
| Player model, poses, look | models/shinty_player.gd (skeleton, actions), models/shinty_player_look.gd (mesh, face, kit), models/shinty_pose_tweaks.gd |
| Grounds | pitch/shinty_pitch.gd plus one file per ground in pitch/venues/; tree and car models in pitch/models/ via pitch/scenery_models.gd |
| TV coverage, replays, graphics, crowd, judges, pre-match, commentary | broadcast/ (commentary lines in data/commentary.json, voice files in audio/commentary/) |
| Menus, loading screen | scripts/main_menu.gd, scripts/loading_screen.gd, ui/ |
| Global state, settings, input bindings | scripts/game.gd (autoload `Game`) |
| Squads, ratings, kits | data/teams.json, scripts/team_data.gd |
| Training ground and pose editor | scripts/practice*.gd, scripts/pose_editor.gd |
| Sound and music | audio/, scripts/music.gd (autoload `Music`) |

Units: the match simulates a flat 2D pitch in yards (x along, y across,
origin in a corner); the 3D world is in metres centred on the centre spot.

## Tests

`GODOT=/path/to/godot tests/run_all.sh quick` runs what CI runs
(.github/workflows/tests.yml, Godot 4.7.2). A test fails on a non-zero exit
or any "SCRIPT ERROR", "Parse Error" or "Failed to load script" in its
output, so one broken script usually fails almost every test. To run one
test: `godot --headless --path . -s tests/<name>_test.gd`. The menu and
render_* tests need a display: `xvfb-run -a godot --path .
--rendering-method gl_compatibility -s tests/<name>.gd`. Run
`godot --headless --import --path .` once after adding files.

## Avoiding merge clashes

Several branches are usually open at once, and the same few places clash:

- tests/run_all.sh: add a new `run` line between two existing lines that no
  other open branch has added next to. Two branches adding a line after the
  same line will clash.
- scripts/game.gd settings and `_setup_input()`, the hub tiles and the
  Controls screen in scripts/main_menu.gd, the help line in scripts/hud.gd:
  add to them, don't rewrite them.
- scripts/match.gd: one thread at a time where possible.
- Enums in pitch/shinty_pitch.gd (`Venue`, `Lighting`): append, don't reorder.

When merging main into a branch, keep both sides' additions unless they
truly replace each other, then run the tests before pushing.

## Gotchas

- Input pressed from a SceneTree script's `_process` is not "just pressed"
  in the next physics step: press from `_physics_process`.
- A freed node is not `== null`; use `is_instance_valid`.
- Headless tests (`-s`) compile match scripts before the autoloads exist:
  there `Game.SOME_CONST` works but `Game.some_var` or `Game.some_func()`
  fails to compile and breaks every test. In scripts the match loads, use
  `get_node_or_null("/root/Game")` instead.
- Never block the main thread waiting on a worker thread that builds
  meshes: the worker may be waiting on the renderer, which runs on the main
  thread, and the game freezes.
- The ground can be built off the main thread (`build_now()`), but
  `_finish_build()` (scenery batching, collision, environment) must run on
  the main thread because it reads meshes back from the renderer.
- Menu music tracks flagged demo_only are not licensed and stay out of the
  repo and release builds (addons/demo_music).
- In the game say "ball" and "goal", not "hail" (the code still uses hail
  for the goal model).
