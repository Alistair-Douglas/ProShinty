class_name ShintyWeather
extends RefCounted
## Match weather: how wet the pitch is, the wind, rain and the light.
##
##  * Wetness (0 dry, 0.5 damp, 1 soaking) changes the ball on the grass: a
##    dry, hard pitch bounces high and runs on, a wet one kills the bounce and
##    holds the ball up. Players lose their footing more on a wet pitch.
##  * Wind pushes the ball in the air, more the higher it goes, so a high
##    ball drifts and a ground ball doesn't. It gusts a little through a match.
##  * Rain and the light (low winter sun, grey skies) are for the eye.
##
## The menu picks one of NAMES (0 = random); make() turns that into the
## dictionary the match keeps as m.weather.

const NAMES := ["Random", "Sunny", "Winter sun", "Overcast", "Drizzle", "Pouring rain"]
enum Kind { RANDOM, SUNNY, WINTER_SUN, OVERCAST, DRIZZLE, POURING }

const MPH_PER_YDS := 2.0455   ## yards/s to miles an hour

## Per kind: pitch wetness, wind range (yards/s at 10 m up), rain (0..1) and
## the ShintyPitch lighting preset.
const KINDS := {
	Kind.SUNNY: {"wet": 0.0, "wind": [0.0, 4.0], "rain": 0.0, "lighting": ShintyPitch.Lighting.SUMMER_AFTERNOON, "pitch": "Dry"},
	Kind.WINTER_SUN: {"wet": 0.4, "wind": [0.5, 5.0], "rain": 0.0, "lighting": ShintyPitch.Lighting.WINTER_SUN, "pitch": "Damp"},
	Kind.OVERCAST: {"wet": 0.5, "wind": [1.5, 7.0], "rain": 0.0, "lighting": ShintyPitch.Lighting.OVERCAST, "pitch": "Damp"},
	Kind.DRIZZLE: {"wet": 0.75, "wind": [2.0, 8.0], "rain": 0.35, "lighting": ShintyPitch.Lighting.RAIN, "pitch": "Wet"},
	Kind.POURING: {"wet": 1.0, "wind": [4.0, 11.0], "rain": 1.0, "lighting": ShintyPitch.Lighting.RAIN, "pitch": "Wet"},
}
## How often each turns up when the menu says Random: it's Scotland.
const ODDS := {Kind.SUNNY: 2, Kind.WINTER_SUN: 2, Kind.OVERCAST: 3, Kind.DRIZZLE: 2, Kind.POURING: 1}


## The match's weather. `pick` is a menu index (Kind), a dictionary already
## made by make(), or null for the old default: a damp, still day (the
## conditions the ball physics were tuned on).
static func make(pick = null) -> Dictionary:
	if pick is Dictionary:
		return pick
	if pick == null:
		return {"kind": -1, "name": "Calm", "wet": 0.5, "wind": Vector2.ZERO, "rain": 0.0,
			"lighting": ShintyPitch.Lighting.SUMMER_AFTERNOON, "pitch": "Damp"}
	var kind := int(pick)
	if kind <= Kind.RANDOM or not KINDS.has(kind):
		var total := 0
		for k in ODDS:
			total += ODDS[k]
		var roll := randi() % total
		for k in ODDS:
			roll -= ODDS[k]
			if roll < 0:
				kind = k
				break
	var spec: Dictionary = KINDS[kind]
	var wind: Array = spec["wind"]
	var speed := randf_range(wind[0], wind[1])
	return {"kind": kind, "name": NAMES[kind], "wet": clampf(spec["wet"] + randf_range(-0.05, 0.05), 0.0, 1.0),
		"wind": Vector2.from_angle(randf() * TAU) * speed, "rain": spec["rain"],
		"lighting": spec["lighting"], "pitch": spec["pitch"]}


## Wind right now: the base wind with slow gusts on top (yards/s, pitch x/y).
static func wind_at(w: Dictionary, t: float) -> Vector2:
	var base: Vector2 = w.get("wind", Vector2.ZERO)
	if base == Vector2.ZERO:
		return base
	var gust := 1.0 + 0.2 * sin(t * 0.37) + 0.12 * sin(t * 1.13 + 1.7)
	return base.rotated(0.12 * sin(t * 0.21)) * gust


## How slippery the pitch is for players: 0 up to damp, 1 when soaking.
static func slip(w: Dictionary) -> float:
	return clampf((float(w.get("wet", 0.5)) - 0.5) * 2.0, 0.0, 1.0)


## "Wet pitch, wind 14 mph" for the HUD and the loading screen.
static func describe(w: Dictionary) -> String:
	var mph := roundi(Vector2(w.get("wind", Vector2.ZERO)).length() * MPH_PER_YDS)
	var wind := "no wind" if mph < 2 else "wind %d mph" % mph
	return "%s pitch, %s" % [w.get("pitch", "Damp"), wind]
