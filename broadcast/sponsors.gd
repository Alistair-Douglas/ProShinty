class_name ShintySponsors
extends RefCounted
## The sponsors on the pitchside boards and on the shirts, from
## data/sponsors.json. Each sponsor has two pictures in broadcast/sponsors/:
##   <id>.png         board artwork, about 6.7:1, full colour
##   <id>_shirt.png   shirt print, about 3:1, white on transparent (the kit's
##                    trim colour is applied when it is printed on a shirt)
## The ones in the repository are made up and drawn by tests/render_sponsors.gd.

const DATA := "res://data/sponsors.json"
const ART := "res://broadcast/sponsors/"

static var _list: Array = []
static var _tex := {}


static func all() -> Array:
	if _list.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if data is Dictionary:
			_list = data.get("sponsors", [])
	return _list


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in all():
		out.append(str(s["id"]))
	return out


static func find(id: String) -> Dictionary:
	for s in all():
		if s["id"] == id:
			return s
	return {}


static func board_texture(id: String) -> Texture2D:
	return _load(ART + id + ".png")


static func shirt_texture(id: String) -> Texture2D:
	return _load(ART + id + "_shirt.png")


## The shirt sponsor for a club: its own "sponsor" id from teams.json if it
## has one, otherwise a steady pick from the list so each club keeps the same
## sponsor from match to match.
static func for_team(team: Dictionary) -> String:
	var own := str(team.get("sponsor", ""))
	if own != "":
		return own
	var list := ids()
	if list.is_empty():
		return ""
	return list[absi(hash(str(team.get("id", team.get("name", ""))))) % list.size()]


static func _load(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]
