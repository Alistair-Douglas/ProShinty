# Scenery models

Tree and car models used in place of the code-built ones (see
`pitch/scenery_models.gd`). glTF (`.glb`/`.gltf`) or `.fbx`, made in metres
with Y up. Only use models you may ship: CC0, CC-BY (credit it in
`CREDITS.md`) or your own.

The start of the file name says what the model is:

- `trees/`: `pine_*`, `birch_*`, `rowan_*`, `beech_*`, `broadleaf_*`, `yew_*`, `bush_*`
- `cars/`: `hatchback_*`, `estate_*`, `saloon_*`, `suv_*`, `landrover_*`, `pickup_*`, `van_*`, `minibus_*`

Add `_far` for a model's far version (`pine_1_far.glb`), seen beyond about
85 m at Medium. Trees without one get a plain crown and trunk sized to fit;
cars without one use Godot's automatic simpler versions.

Budgets, since each is drawn many times: trees 300 to 1,500 triangles (far
version 100 to 200), bushes under 200, cars 500 to 3,000. One or two
materials each; leaves as cut-out (alpha scissor) cards on a small texture.
Car materials named with `paint`, `body` or `main` get a random colour per car.

## Where these came from (all CC0, public domain)

- `trees/`: Quaternius, Ultimate Nature Pack (https://quaternius.com/packs/ultimatenature.html):
  BirchTree, PineTree and CommonTree 1 to 3 as `birch_`, `pine_` and `broadleaf_`; Bush 1 and 2.
- `cars/`: Kenney, Car Kit (https://kenney.nl/assets/car-kit): hatchback-sports, sedan,
  suv, suv-luxury, van and truck, with `Textures/colormap.png`.
