extends RefCounted
## Loads squads from data/teams.json and works out player overall ratings.
## To use real squads, edit the JSON: each team needs 12 players, one per
## position code listed in FORMATION. Extra players are kept as substitutes.

const PATH := "res://data/teams.json"

## Formation spot for each position, as a fraction of the pitch.
## x runs from the team's own goal (0) to the goal it attacks (1).
const FORMATION := {
	"GK": Vector2(0.02, 0.5),
	"FB": Vector2(0.13, 0.5),
	"LHB": Vector2(0.26, 0.2),
	"CHB": Vector2(0.26, 0.5),
	"RHB": Vector2(0.26, 0.8),
	"LM": Vector2(0.45, 0.35),
	"RM": Vector2(0.45, 0.65),
	"LHF": Vector2(0.62, 0.2),
	"CHF": Vector2(0.62, 0.5),
	"RHF": Vector2(0.62, 0.8),
	"CF": Vector2(0.75, 0.38),
	"FF": Vector2(0.86, 0.6),
}

const ROLE := {
	"GK": "GK",
	"FB": "DEF", "LHB": "DEF", "CHB": "DEF", "RHB": "DEF",
	"LM": "MID", "RM": "MID",
	"LHF": "FWD", "CHF": "FWD", "RHF": "FWD", "CF": "FWD", "FF": "FWD",
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


static func role_of(position_code: String) -> String:
	return ROLE.get(position_code, "MID")


static func overall(p: Dictionary) -> int:
	var w: Dictionary = WEIGHTS[role_of(str(p.get("position", "")))]
	var sum := 0.0
	for k in w:
		sum += float(p.get(k, 50)) * w[k]
	return roundi(sum)


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
