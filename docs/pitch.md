# Shinty grounds (3D)

`pitch/shinty_pitch.tscn` (class `ShintyPitch`) builds a full shinty pitch at
a real ground. Pick the ground with `venue`; the menu's **Pitch** option sets
it for a match, and picking a home team moves the match to that team's ground.

| Venue | Laid out from |
| --- | --- |
| Aberdour | Alistair's three photos and a satellite view of the club |
| Kingussie (The Dell) | A satellite view of the club |
| Tighnabruaich (Kyles Athletic) | An aerial photo of the ground |

## The pitch

- Real shinty dimensions: 150 x 75 yards by default (rules allow 140 to 170 by
  70 to 80), matching the match simulation. Markings: sidelines, bylines,
  halfway line, 5-yard centre circle and spot, the 10-yard D at each hail,
  penalty spots at 20 yards with 5-yard arcs, 2-yard corner arcs. The ground
  shader draws them, so they stay sharp and follow any pitch size.
- Mowing stripes, worn goalmouths, placeholder hails (12 ft x 10 ft), corner
  and halfway flags, and a physics floor (StaticBody3D, layer 1).
- Lighting presets: summer afternoon, summer evening, overcast. Custom sky
  with sun-lit cumulus and high wisps, blue distance haze, soft four-split
  shadows, AgX tone mapping and glow.
- Trees are trunks and limbs with leafy canopies (cut-out leaf cards that sway
  in the wind); long grass grows in tufts at the pitch edges; the sea and the
  Spey use a water shader with moving waves and sky reflection.
- The game runs on the Forward+ renderer, which adds ambient occlusion,
  indirect light and reflections; machines that can't run it fall back to
  Compatibility automatically.

## The grounds

**Aberdour.** The pitch runs west to east. North: a footpath, long grass and
earthworks, the fenced railway on a low embankment, then Brachi Woods rising
to Hawkcraig, with houses to the north-west. South: the avenue of trees along
the path, with cars parked under it, and Hawkcraig Park's fields and
hedgerows beyond. East: paths, a timber hut, the walled garden, then
Silversands beach and the Forth, with the café by the beach, Inchcolm and its
abbey out in the water and the Lothian shore on the horizon. West: a car park
behind the hail and the village.

**Kingussie, The Dell.** The real pitch runs north-west to south-east; in the
game its long axis is X like every ground, so the west hail is the north-west
end. A white rail runs round the pitch and the grass is striped lengthways.
Behind the west hail: the covered stand and a club hut. North side (the far
side on the match camera): dugouts either side of halfway, a portakabin and a
container, and the big gravel car park, with young plantations, the track up
to the town, and Kingussie itself on the slope beyond. South side and east
end: birch and alder along the River Spey, which curves round the ground,
and the A9 beyond the bend. Behind the east hail: a tall ball-stop net. Hills
all round, highest to the east (the Cairngorms).

**Tighnabruaich, Kyles Athletic.** The pitch sits on the shore of the Kyles
of Bute. North (far side): a grassy bank up to the village road with lamp
posts, then the wooded hillside, with villas above the west end. South: the
sea wall and a white rail, shingle, the Kyles with moored boats, and Bute
across the water. East: the car park, the clubhouse, a fenced tennis court and
a play area. West: a tall ball-stop net and a cottage by the shore.

## Using it

1. Instance `pitch/shinty_pitch.tscn`. The pitch is centred on the node:
   length along X, width along Z, west hail at -X, the far touchline at -Z.
   1 unit = 1 metre by default; `units_per_yard = 1.0` works in yards (the
   match does this).
2. Convert simulation positions in yards (origin in a corner) with
   `sim_to_world(Vector2(x, y), height_yd)` and back with `world_to_sim()`.
3. Place goal models with `goal_transform(0)` (west) and `goal_transform(1)`
   (east): origin on the centre of the goal line, -Z pointing out of the
   pitch. Then set `show_placeholder_goals = false`.
4. Set `include_environment = false` if the scene has its own sky and sun.
5. The camera needs `far` of about 6000 to reach the horizon hills.

Settings: `venue`, `length_yd`, `width_yd`, `lighting`, `scenery_detail`
(LOW/MEDIUM/HIGH, mostly tree density), `show_scenery`, `show_flags`,
`grass_wear` (-1 uses the ground's own look), `layout_seed`.
`ground_height(p)` gives the land height at a point.

## Adding a ground

Add a script to `pitch/venues/` with the same functions as `aberdour.gd`
(`height_m`, `ground_mask`, `ground_look`, `water`, `fog_density`,
`extra_cloud`, `build`), then add it to `Venue`, `VENUE_NAMES` and the file
list in `_rebuild()` in `shinty_pitch.gd`. The building blocks in
`shinty_pitch.gd` (trees, houses, cars, fences, roofs) are there to reuse.

## Files

- `pitch/shinty_pitch.gd`: the pitch, markings, lighting, public API and
  shared building blocks.
- `pitch/venues/aberdour.gd`, `pitch/venues/kingussie.gd`: each ground's land,
  ground colours and scenery.
- `pitch/ground.gdshader`: grass, markings, earth, gravel, sand and shingle.
- `pitch/canopy.gdshader`: lumpy tree canopies.
- `pitch/sky.gdshader`: sky, sun and clouds.
- `preview/`: orbit preview. F6 on `preview.tscn`; 1 to 6 for views (6 is
  the match camera), L for lighting, V to switch ground.
- `tests/render_views.gd`: renders every view of both grounds to `renders/`
  and checks the coordinate helpers:
  `xvfb-run godot --path . --rendering-method gl_compatibility -s tests/render_views.gd`

## Known gaps

- Layouts come from photos and satellite views, not a survey, so positions
  are approximate and everything is low detail.
- The renders come from Godot's software Compatibility renderer.
