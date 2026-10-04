# Shinty models

3D player, ball and hail (goal) for the shinty game, plus the physics of
hitting the ball with the caman. Godot 4.7, GDScript, GL Compatibility.
Everything is built in code from Godot primitives (no imported art), so the
models scale and recolour from the squad data. Free CC0 packs (Kenney,
Quaternius) could not be downloaded from this environment, and a procedural
build is easier to drive from stats anyway. The skeleton uses Godot's
humanoid bone names, so a skinned character from an artist can replace the
meshes later.

## Try it

Open this folder's `project.godot` in Godot 4.7 and press F5. The showcase
shows both squads lined up, a forward hitting balls at the hail and a keeper
diving. Keys: 1 to 4 change camera, Space hits now, L toggles lofted hits.

Tests: `godot --headless --path . -s tests/model_test.gd` (64 checks).

## What's here

| File | What it is |
| --- | --- |
| `models/shinty_player.gd` / `.tscn` | `ShintyPlayerModel`: rigged, animated player with helmet, kit, number and caman |
| `models/shinty_ball.gd` / `.tscn` | `ShintyBallModel`: ball with seam, spin, shadow and landing marker |
| `models/shinty_ball_physics.gd` | `ShintyBallPhysics`: gravity, air drag, spin lift, bounce and roll |
| `models/shinty_hail.gd` / `.tscn` | `ShintyHailModel`: posts, crossbar, rippling net; post/net collisions and goals |
| `models/shinty_strike.gd` | `ShintyStrike`: what happens when the caman meets the ball |
| `models/shinty_match_adapter.gd` | `ShintyMatchAdapter`: drop-in glue for shinty-game's match (yards) |

All models use metres, stand on y = 0 and face -Z.

### Player

- `setup(player, team)` takes the dictionaries from `data/teams.json`.
- **Size from stats.** Height and build come from `height_cm` and `weight_kg`
  if the player has them. Otherwise they are worked out from the ratings:
  good tacklers are bigger, quick players leaner, keepers a little taller, with
  a steady per-player variation. See `ShintyPlayerModel.body_from_stats()`.
  Add `height_cm` and `weight_kg` to a player in `teams.json` to set them
  exactly. `hand: "L"` makes a left-hander; `skin: "#rrggbb"` sets skin tone.
- **Faces from squad data.** Optional player keys: `hair` (a colour name:
  black, dark, brown, mid, light, fair, blond, red, ginger, grey, white; or a
  hex colour), `hair_style` (`crop`, `buzz`, `long`) and `facial_hair`
  (`none`, `stubble`, `beard`, `goatee`, `moustache`). Anything left out is
  picked from the player's seed, so the same player always looks the same.
- **Colours from team data.** Shirt = `primary`, trim and shorts =
  `secondary`, socks and helmet = `primary`. Optional team colour keys
  `helmet`, `shorts`, `socks` and `keeper` override those. Keepers get a shirt
  picked to stand out from both team colours.
- **Animation.** `set_locomotion(velocity)` drives idle, jog and sprint (feet
  stay on the ground). `play_action(name, power, contact_height)` plays
  `swing`, `pass`, `volley`, `tackle`, `trap`, `save_left`, `save_right` or
  `celebrate`. `charge_swing()` / `release_swing(power)` hold the caman back
  while the hit button is held. `look_at_point(pos)` turns the head.
- **Hit timing.** The `strike(head_position, power)` signal fires at the
  contact frame. `time_to_contact()` says how long after `play_action` that is.
  `get_strike_spot()` is where the ball should sit for a ground hit.

### How players look

`models/shinty_player_look.gd` (`ShintyPlayerLook`) hangs every mesh on the
skeleton; `models/shinty_mesh.gd` (`ShintyMesh`) has the mesh and material
helpers. The skeleton, bones, `Caman` node and animation code in
`shinty_player.gd` are unchanged, so the look can change without touching
animation or physics.

- **Bodies** are smooth swept shapes rather than capsules: shoulders slope
  into the arms, thighs and calves have muscle shape, and build changes girth
  and shoulder width.
- **Hands** grip the caman properly: four fingers curl round the 2.5 cm grip
  and the thumb wraps the other way. The arm solver turns each hand so the
  shaft runs across the palm, with the top hand at the butt; if the lower hand
  can't reach its spot it slides up the shaft rather than letting go.
- **Faces** have a jaw, cheekbones, nose, brow, lips, eyes (whites, iris,
  pupil), eyebrows and ears. Jaw width, chin length, cheeks and nose size
  vary per player, as do hair colour, eye colour, hair style (a crop, a buzz
  cut, or long hair showing below the helmet) and facial hair (stubble, a
  beard, a goatee or a moustache; a bit over half of players have some). Skin
  uses a shader with a slight warm edge; stubble uses the same shader in a
  darker tone.
- **Kit** uses a fabric shader with a fine knit and soft folds, a chest band
  and cuffs in the trim colour, a collar, a crest on the left breast, a small
  number on the front, and the number and surname on the back (surnames show
  once squads have real names). Socks have trim hoops. A team can set
  `colors.pattern` to `"hoops"` or `"stripes"`.
- **Boots** are low-cut football boots: a flat sole plate with a little toe
  spring, a heel collar round the ankle, a lace panel over the instep, a
  wide forefoot turned in at the big toe, a side flash, and conical studs.
  Boot, sole and flash colours vary across the squad.
- **Helmet** follows the hurling-style helmets players wear: a rounded shell
  that comes down past the ears, a raised crown panel from brow to nape,
  slotted vents on the forehead, top and sides, white foam lining under the
  brow and down the cheeks, rivets at the temples, a made-up "CORRIE" brand
  on each side, and a steel cage (seven bars across, six up) standing off
  the face and tucking in under the chin, with a chin cup and strap. Most
  players wear the team's helmet colour; about one in six wears a white
  shell and about one in seven a two-tone one with the panel in the trim
  colour (keepers always wear the team colour).
- **Caman**: ash grain, an oval shaft that flares into a curved bas, grip
  tape spiralled round the handle, a knob at the end and tape on the bas.
- **Ball**: leather with a stitched seam drawn by a shader, and a raised ridge
  so spin reads from a distance.

### Ball and hitting

- `ShintyStrike.compute({...})` returns the ball's velocity and spin after a
  hit. It treats the hit as a collision between the caman head and the ball:
  power and the shooting (or passing) rating set head speed; a ball coming
  towards the player goes back faster; an off-centre contact (the real
  distance from the caman head to the ball) loses pace and direction; better
  players are more accurate; control reduces mishits; loft sets launch angle
  and backspin. A top hit is about 45 m/s (163 km/h).
- `ShintyStrike.hit(player_model, ball_model, aim, power, loft)` does all of
  that with the models' real positions.
- `ShintyBallPhysics` flies the ball with gravity, air drag and spin lift,
  bounces it on grass and rolls it to a stop. A 40 m/s lofted hit carries
  about 107 m; a 20 m/s ground ball rolls about 51 m. `predict_landing()`
  gives where a high ball comes down (for AI and the marker).
- `ShintyStrike.power_for_distance()` gives the power for a pass or lob of a
  given length (for AI).

### Hail

12 ft between the posts, 10 ft to the bar, with a net frame. The ball rebounds
off posts and crossbar, the net swallows it and ripples, and a goal counts
only when the whole ball crosses the line between the posts and under the
bar. A ball going into the net from behind does not count.

## Plugging into shinty-game

`integration.patch` does the whole swap against shinty-game as it stood on
2026-09-27 (after the move to 3D and the new pitch). I applied it to a
scratch copy: all six computer-vs-computer matches in `tests/sim_test.gd`
reached full time (17 goals, against 18 without the patch), and the real game ran with the new
players, ball and hails. To use it:

1. Copy `models/` into the game as `res://models/` (the classes register by
   name, so nothing needs preloading).
2. From the shinty-game folder: `patch -p1 < ../shinty-models/integration.patch`

What the patch changes:

- **Players** (`match_view.gd`): `_build_player()` calls
  `ShintyMatchAdapter.build_player()` with the match's colours (so the clash
  swap still works) and keeps the ring, arrow and tag. `_update_player()`
  drops the leg and caman rotations and the bob, and calls
  `ShintyMatchAdapter.update_player(f, p.vel, p.swing, false, ball_pos)`.
  The returned dictionary still has `leg_l`, `leg_r` and `caman` as empty
  pivots, so any other code that rotates them does no harm.
- **Ball** (`match_view.gd`): a `ShintyBallModel` with `simulate = false`,
  scaled to yards and drawn 4x size so it reads from the broadcast camera,
  with its own shadow.
- **Hails** (`match_view.gd`): a `ShintyHailModel` in each of the pitch's goal
  frames, turned round because the pitch's frame has the net towards -Z.
- **Hitting** (`match.gd`, `_strike_speed`): the match still decides the
  speed and upward speed it wants; `ShintyMatchAdapter.strike_like_match()`
  turns that into a swing power and loft for the player's rating and runs the
  strike physics, so rating, difficulty modifier, incoming ball speed and
  mishits all count. The old random-error line is gone (the physics adds it).
- **Ball flight** (`match.gd`, `_update_ball`): the free-ball integration is
  replaced by `ball_sim.step(self, dt)` (`ShintyMatchAdapter.BallSim`), which
  adds air drag, spin, grass roll, and post, crossbar and net collisions. It
  returns events (`bounce`, `post`, `net`, `goal` with `end` 0 or 1) if the
  match wants them; the existing goal-line check still works as it is.

Worth knowing: balls now slow down more on grass, so there were fewer shies
and hit-outs in the test matches (6 shies against 33). Tune `ROLL_DECEL` and
`ROLL_DRAG` in `shinty_ball_physics.gd` if that feels wrong in play.

Hit timing: match.gd launches the ball the moment it decides to hit, so the
adapter starts the swing at the top of the backswing to keep the picture
close. For a full swing, delay the launch by `model.time_to_contact()` or
launch on the model's `strike` signal.

## Performance

Each player is about 15,100 triangles, baked into one skinned mesh of about
nine surfaces (ten with stubble) (one per material; every plain-coloured part shares a single
surface) plus a shadow-only copy. The helmet cage, boots and vents add
triangles but no draw calls. `low_detail = true` halves the triangles (about
8,400) by leaving out the face details, most cage bars, vents, studs, laces,
names and numbers; use it for distant players.
