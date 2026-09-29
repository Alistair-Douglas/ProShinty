extends RefCounted
## Loads squads from data/teams.json and works out player overall ratings.
## To use real squads, edit the JSON: each team needs 12 players, one per
## position code listed in FORMATION. Extra players are kept as substitutes.

const PATH := "res://data/teams.json"
## Club crests, one PNG per team id (e.g. data/logos/kingussie.png).
const LOGO_DIR := "res://data/logos"

## Formation spot for each position, as a fraction of the pitch.
## x runs from the team's own goal (0) to the goal it attacks (1).
## A 4-3-4 and a keeper: the full back and three half backs, three in the
## middle (the centre half forward plays as the middle one of the three), and
## four forwards. The forwards stand in a diamond or a square (FORWARD_SHAPES),
## and the backs line up on the forwards they mark, so the back four take the
## same shape as the other team's front four.
const FORMATION := {
	"GK": Vector2(0.02, 0.5),
	"FB": Vector2(0.10, 0.5),
	"LHB": Vector2(0.22, 0.2),
	"CHB": Vector2(0.33, 0.5),
	"RHB": Vector2(0.22, 0.8),
	"LM": Vector2(0.46, 0.25),
	"CHF": Vector2(0.43, 0.5),
	"RM": Vector2(0.46, 0.75),
	"LHF": Vector2(0.74, 0.2),
	"CF": Vector2(0.62, 0.5),
	"RHF": Vector2(0.74, 0.8),
	"FF": Vector2(0.88, 0.5),
}

## The front four: a diamond (one up top, two wide, one in the hole) or a
## square (two pairs).
const FORWARD_SHAPES := {
	"diamond": {"CF": Vector2(0.62, 0.5), "LHF": Vector2(0.74, 0.2), "RHF": Vector2(0.74, 0.8), "FF": Vector2(0.88, 0.5)},
	"square": {"LHF": Vector2(0.66, 0.28), "RHF": Vector2(0.66, 0.72), "CF": Vector2(0.84, 0.36), "FF": Vector2(0.84, 0.64)},
}

## Shinty is man-marking, back against forward: which opposing forward each
## back picks up.
const MARKS := {"FB": "FF", "CHB": "CF", "LHB": "LHF", "RHB": "RHF"}
const MARK_GAP := 0.035   ## backs stand this far goal-side of their forward (fraction of the length)

const ROLE := {
	"GK": "GK",
	"FB": "DEF", "LHB": "DEF", "CHB": "DEF", "RHB": "DEF",
	"LM": "MID", "CHF": "MID", "RM": "MID",
	"LHF": "FWD", "RHF": "FWD", "CF": "FWD", "FF": "FWD",
}

const POSITION_NAMES := {
	"GK": "Goalkeeper", "FB": "Full Back",
	"LHB": "Left Half Back", "CHB": "Centre Half Back", "RHB": "Right Half Back",
	"LM": "Left Centre", "RM": "Right Centre",
	"LHF": "Left Half Forward", "CHF": "Centre Half Forward", "RHF": "Right Half Forward",
	"CF": "Centre Forward", "FF": "Full Forward",
}

const WEIGHTS := {
	"GK": {"keeping": 0.7, "control": 0.1, "passing": 0.1, "pace": 0.1},
	"DEF": {"tackling": 0.35, "pace": 0.2, "passing": 0.2, "control": 0.15, "shooting": 0.1},
	"MID": {"passing": 0.3, "control": 0.25, "pace": 0.2, "tackling": 0.15, "shooting": 0.1},
	"FWD": {"shooting": 0.35, "control": 0.25, "pace": 0.25, "passing": 0.15},
}

const STAT_KEYS := ["pace", "control", "passing", "shooting", "tackling", "keeping", "stamina"]


## Why the last load_teams() call dropped data, shown on the menu. Empty if fine.
static var load_error := ""


static func load_teams() -> Array:
	load_error = ""
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		load_error = "Could not open %s (%s)." % [PATH, error_string(FileAccess.get_open_error())]
		push_error(load_error)
		return []
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		load_error = "%s has a mistake on line %d: %s" % [PATH, json.get_error_line(), json.get_error_message()]
		push_error(load_error)
		return []
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("teams")) != TYPE_ARRAY:
		load_error = "%s needs a \"teams\" list." % PATH
		push_error(load_error)
		return []
	var teams := []
	var problems := []
	for team in parsed["teams"]:
		if typeof(team) != TYPE_DICTIONARY or typeof(team.get("players")) != TYPE_ARRAY:
			problems.append("a team entry has no \"players\" list")
			continue
		team["name"] = str(team.get("name", team.get("id", "Team")))
		var players := []
		for p in team["players"]:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			for k in STAT_KEYS:
				p[k] = int(p.get(k, 50))
			p["number"] = int(p.get("number", 0))
			p["name"] = str(p.get("name", "Player %d" % p["number"]))
			p["position"] = str(p.get("position", ""))
			p["overall"] = overall(p)
			players.append(p)
		team["players"] = players
		var starters := starting_twelve(team)
		if starters.size() < FORMATION.size():
			var missing := []
			for pos in FORMATION:
				if not starters.any(func(q): return q["position"] == pos):
					missing.append(pos)
			problems.append("%s has no player at %s" % [team["name"], ", ".join(missing)])
			continue
		var total := 0
		for p in starters:
			total += p["overall"]
		team["overall"] = roundi(float(total) / starters.size())
		teams.append(team)
	if not problems.is_empty():
		load_error = "Skipped in %s: %s." % [PATH, "; ".join(problems)]
		push_warning(load_error)
	return teams


## Home spots for a team whose forwards play `shape`, against opponents whose
## forwards play `their_shape`: the backs line up goal-side of the forwards
## they mark.
static func shaped_home(position_code: String, shape: String, their_shape: String) -> Vector2:
	var fwd: Dictionary = FORWARD_SHAPES.get(shape, FORWARD_SHAPES["diamond"])
	if fwd.has(position_code):
		return fwd[position_code]
	if MARKS.has(position_code):
		var theirs: Dictionary = FORWARD_SHAPES.get(their_shape, FORWARD_SHAPES["diamond"])
		var f: Vector2 = theirs[MARKS[position_code]]
		return Vector2(1.0 - f.x - MARK_GAP, f.y)
	return FORMATION.get(position_code, Vector2(0.5, 0.5))


static func role_of(position_code: String) -> String:
	return ROLE.get(position_code, "MID")


static func overall(p: Dictionary) -> int:
	var w: Dictionary = WEIGHTS[role_of(str(p.get("position", "")))]
	var sum := 0.0
	for k in w:
		sum += float(p.get(k, 50)) * w[k]
	return roundi(sum)


## Path of the team's crest, or "" if there isn't one.
static func logo_path(team: Dictionary) -> String:
	var path := "%s/%s.png" % [LOGO_DIR, str(team.get("id", ""))]
	return path if ResourceLoader.exists(path) else ""


## The team's crest texture, or null if there isn't one.
static func logo(team: Dictionary) -> Texture2D:
	var path := logo_path(team)
	return load(path) if path != "" else null


## First player listed at each position; anyone else is a substitute.
static func starting_twelve(team: Dictionary) -> Array:
	var picked := {}
	var out := []
	for p in team["players"]:
		var pos: String = p.get("position", "")
		if FORMATION.has(pos) and not picked.has(pos):
			picked[pos] = true
			out.append(p)
	return out


# ---------------------------------------------------------------- kits

## Kits the away side can fall back on when both its own kits clash.
const SPARE_KITS := [
	{"primary": "#f4f4f4", "secondary": "#16161a", "shorts": "#16161a", "socks": "#f4f4f4"},
	{"primary": "#16161a", "secondary": "#f4f4f4", "shorts": "#16161a", "socks": "#16161a"},
	{"primary": "#f6c700", "secondary": "#16161a", "shorts": "#16161a", "socks": "#f6c700"},
	{"primary": "#6cb4e4", "secondary": "#16254f", "shorts": "#16254f", "socks": "#6cb4e4"},
]
## Shirts closer than this (see colour_distance) are too alike to tell apart.
const CLASH_DISTANCE := 0.8


## A team's home kit: colors without the change kit or notes.
static func home_kit(team: Dictionary) -> Dictionary:
	var c: Dictionary = team.get("colors", {}).duplicate()
	c.erase("away")
	c.erase("source")
	c.erase("placeholder")
	return c


## A team's change kit, or {} if it has none.
static func away_kit(team: Dictionary) -> Dictionary:
	var a = team.get("colors", {}).get("away", {})
	return a if typeof(a) == TYPE_DICTIONARY else {}


## The kits for a match, [home, away]. The home side wears its home kit; the
## away side wears its home kit too unless the shirts clash, then its change
## kit, then a spare.
static func match_kits(home: Dictionary, away: Dictionary) -> Array:
	var h := home_kit(home)
	for k in [home_kit(away), away_kit(away)] + SPARE_KITS:
		if not k.is_empty() and not kits_clash(h, k):
			return [h, k]
	return [h, SPARE_KITS[0]]


## True if two kits' shirts look too alike. Hooped and striped shirts count
## both of their colours.
static func kits_clash(a: Dictionary, b: Dictionary) -> bool:
	for x in shirt_colours(a):
		for y in shirt_colours(b):
			if colour_distance(x, y) < CLASH_DISTANCE:
				return true
	return false


static func shirt_colours(kit: Dictionary) -> Array:
	var out := [Color(str(kit.get("primary", "#cc2222")))]
	if str(kit.get("pattern", "")) != "":
		out.append(Color(str(kit.get("secondary", "#ffffff"))))
	return out


## How different two colours look (weighted RGB, 0 to about 3).
static func colour_distance(a: Color, b: Color) -> float:
	var rm := (a.r + b.r) / 2.0
	return sqrt((2.0 + rm) * pow(a.r - b.r, 2) + 4.0 * pow(a.g - b.g, 2) + (3.0 - rm) * pow(a.b - b.b, 2))


## Referee's shirt colour for a match: black, or a bright top if a team's
## shirt is too close to black.
static func referee_colour(kits: Array) -> String:
	for c in ["#15161a", "#c6e21c", "#ff7ab8"]:
		var ref := {"primary": c}
		if not kits.any(func(k): return kits_clash(ref, k)):
			return c
	return "#15161a"
