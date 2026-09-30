extends SceneTree
## Bakes the patterns the scenery shaders used to compute per pixel into small
## textures, so drawing them costs one or two texture reads instead of dozens
## of noise evaluations. Run after changing the patterns:
##   godot --headless --path . -s tools/bake_scenery_textures.gd
##
## pitch/leaves.png: the leaf-cluster cut-out for tree canopy cards (four
##   variants in a 2x2 atlas), the same pattern canopy.gdshader drew before.
## pitch/leaves_tile.png: a copy of leaves.png imported with mipmaps, tiled
##   over the far trees.
## pitch/ground_noise.png: tileable value noise for ground.gdshader.
##   r = 4-octave fbm, g = 4-octave fbm (other seed), b = single-octave noise.

const LEAF := 128        # pixels per leaf variant
const LEAF_DENSITY := 3.2
const NOISE := 256       # pixels across the ground noise tile
const CELLS := 32        # noise cells across the tile (base octave)


func _initialize() -> void:
	_bake_leaves()
	_bake_noise()
	quit()


# --- the same hashes as the shaders ---

static func _fract(x: float) -> float:
	return x - floorf(x)


static func _hash2(p: Vector2) -> float:
	p = Vector2(_fract(p.x * 123.34), _fract(p.y * 456.21))
	var d := p.dot(p + Vector2(45.32, 45.32))
	p += Vector2(d, d)
	return _fract(p.x * p.y)


func _leaves(uv: Vector2, seed: float) -> float:
	var g := uv * LEAF_DENSITY
	var c := g.floor()
	var a := 0.0
	for j in range(-1, 2):
		for i in range(-1, 2):
			var cc := c + Vector2(i, j)
			var o := Vector2(_hash2(cc + Vector2.ONE * seed * 13.0), _hash2(cc + Vector2.ONE * seed * 13.0 + Vector2.ONE * 1.7))
			var d := g - (cc + o)
			var ang := _hash2(cc + Vector2.ONE * 5.3) * TAU
			d = Vector2(cos(ang) * d.x - sin(ang) * d.y, sin(ang) * d.x + cos(ang) * d.y)
			d.x *= 1.7
			a = maxf(a, 1.0 - d.length() / 0.62)
	return clampf(a, 0.0, 1.0)


func _bake_leaves() -> void:
	var img := Image.create(LEAF * 2, LEAF * 2, false, Image.FORMAT_L8)
	for v in 4:
		var seed: float = [0.13, 0.41, 0.67, 0.89][v]
		var ox := (v % 2) * LEAF
		var oy := (v / 2) * LEAF
		for y in LEAF:
			for x in LEAF:
				var a := _leaves(Vector2((x + 0.5) / LEAF, (y + 0.5) / LEAF), seed)
				img.set_pixel(ox + x, oy + y, Color(a, a, a))
	img.save_png("res://pitch/leaves.png")
	# The same image, imported with mipmaps, tiles over the far trees' blobs.
	img.save_png("res://pitch/leaves_tile.png")
	print("saved pitch/leaves.png and leaves_tile.png")


# Value noise on a grid of `period` cells that wraps, so the tile repeats cleanly.
func _vnoise(p: Vector2, period: int, salt: float) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var h := func(cx: float, cy: float) -> float:
		return _hash2(Vector2(posmod(int(cx), period) + salt, posmod(int(cy), period) + salt * 1.3))
	var a: float = h.call(i.x, i.y)
	var b: float = h.call(i.x + 1, i.y)
	var c: float = h.call(i.x, i.y + 1)
	var d: float = h.call(i.x + 1, i.y + 1)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


func _fbm(p: Vector2, salt: float) -> float:
	var v := 0.0
	var amp := 0.5
	var period := CELLS
	for o in 4:
		v += amp * _vnoise(p, period, salt + o * 7.0)
		p *= 2.0
		period *= 2
		amp *= 0.5
	return v / 0.9375  # 0..1


func _bake_noise() -> void:
	var img := Image.create(NOISE, NOISE, false, Image.FORMAT_RGB8)
	for y in NOISE:
		for x in NOISE:
			var p := Vector2(x + 0.5, y + 0.5) / NOISE * CELLS
			img.set_pixel(x, y, Color(_fbm(p, 3.0), _fbm(p, 29.0), _vnoise(p * 2.0, CELLS * 2, 61.0)))
	img.save_png("res://pitch/ground_noise.png")
	print("saved pitch/ground_noise.png")
