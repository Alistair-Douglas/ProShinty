# Shinty pitch (3D)

A reusable Godot 4 pitch scene modelled on Aberdour's ground, built from
Alistair's three photos (the Google Maps link could not be opened from the
build environment). Tested in Godot 4.7.

## What's in it

- Pitch at real shinty dimensions: 150 x 75 yards by default (rules allow 140 to
  170 by 70 to 80), matching the 2D game. Markings: sidelines, bylines,
  halfway line, 5-yard centre circle and spot, the 10-yard D at each hail,
  penalty spots at 20 yards with 5-yard arcs, 2-yard corner arcs. Markings are
  drawn by the ground shader, so they stay sharp and follow any pitch size.
- Mowing stripes and worn goalmouths, dry summer patches (`grass_wear`).
- Placeholder hails (12 ft x 10 ft), corner and halfway flags.
- Scenery, low detail: tree-lined south touchline with cars and a van parked
  under the trees; the clump of big dark round trees on the north side;
  long grass, bushes, earthworks, soil heaps, a fence and a timber hut at the
  foot of the wooded hill (north-east); a car park behind the west hail;
  cottages on the rise to the west and north-west; beach and the Firth of
  Forth to the south with the far shore on the horizon.
- Lighting presets: summer afternoon (photo 1), summer evening (photo 3),
  overcast. Custom sky with clouds, fog/haze, shadows.
- A physics floor (StaticBody3D, layer 1).

## Look at it

Open this folder's `project.godot` in Godot and press F5. Drag to orbit,
scroll to zoom, WASD to move. Keys 1 to 5 jump to set views, L cycles the
lighting. Renders of each view are in `renders/`.

## Plug it into the game

1. Copy the `pitch/` folder into the game project (any path works, the
   script finds its shaders next to itself).
2. In the 3D match scene, instance `pitch/shinty_pitch.tscn` (or add a Node3D
   with `shinty_pitch.gd`). The pitch is centred on the node: length along X,
   width along Z, west hail at -X, north touchline at -Z. 1 unit = 1 metre by
   default; set `units_per_yard = 1.0` to work in yards instead. The 3D match
   view in shinty-game (`scripts/match_view.gd`) uses 1 unit = 1 yard with the
   origin on the centre spot, so there: put the pitch at the origin and set
   `units_per_yard = 1.0`.
3. Convert the simulation's yard positions (origin in a corner, as in
   `scripts/match.gd`) with `pitch.sim_to_world(Vector2(x, y), height_yd)` and
   back with `world_to_sim()`.
4. Place the real goal models with `pitch.goal_transform(0)` (west) and
   `goal_transform(1)` (east): origin on the centre of the goal line, the
   basis's -Z points out of the pitch. Then set `show_placeholder_goals = false`.
5. If the match scene has its own WorldEnvironment or sun, set
   `include_environment = false`. Otherwise leave it on.
6. The camera needs `far` of about 6000 to see the far shore. There is a
   `Generated/BroadcastCamera` marker above the south touchline as a starting
   camera position.

Useful settings: `length_yd`, `width_yd`, `lighting`, `scenery_detail`
(LOW/MEDIUM/HIGH, mostly woodland density), `show_scenery`, `show_flags`,
`grass_wear`, `layout_seed`. `ground_height(p)` gives the land height at a
point if anything needs placing on the hills.

## Files

- `pitch/shinty_pitch.gd`: builds everything (pitch, scenery, lighting) and the API above.
- `pitch/ground.gdshader`: grass, markings, earth, gravel and sand.
- `pitch/canopy.gdshader`: lumpy tree canopies.
- `pitch/sky.gdshader`: sky, sun and clouds.
- `preview/`: the preview scene and orbit camera.
- `tests/render_views.gd`: renders the views to `renders/` and checks the
  coordinate helpers. Run:
  `xvfb-run godot --path . --rendering-method gl_compatibility -s tests/render_views.gd`

## Known gaps

- Layout is from the photos, not a survey: tree positions, the hill and the
  houses are approximate. A screenshot of the Google Earth view would let it
  be matched more closely.
- The renders in `renders/` come from Godot's software Compatibility renderer.
  On a normal PC with Forward+ you also get ambient occlusion and glow.
