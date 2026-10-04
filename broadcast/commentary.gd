class_name ShintyCommentary
extends Control
## Match commentary: a line of generic Scots-flavoured patter for what the
## match just did (a big hit, a save, a goal, a foul, half time), shown as a
## caption top centre and spoken if a voice recording of that line exists.
## Lines live in data/commentary.json; voice files in audio/commentary/ (see
## the README there). Like the match sound it only reads match.events, the
## referee's calls and cards and the ball's post hits, so the match knows
## nothing about it.

const LINES_PATH := "res://data/commentary.json"
## Voice files: res:// ones ship with the game; user:// ones override them so
## a recording can be tried without re-importing (see audio/commentary/README.md).
const VOICE_DIRS := ["user://commentary/", "res://audio/commentary/"]
const VOICE_EXTS := ["ogg", "mp3", "wav"]

## Which lines win: a line only cuts in on one with a lower priority.
const PRIORITY := {
	"goal": 10, "goal_equaliser": 10, "goal_late": 10, "red_card": 9,
	"match_start": 8, "second_half": 8, "half_time": 8, "extra_time": 8, "full_time": 8,
	"penalty": 8, "shootout_start": 8, "shootout_score": 8, "shootout_miss": 8,
	"save": 7, "post": 7, "yellow_card": 7, "no_goal": 7,
	"wide": 6, "foul": 5, "offside": 5, "foul_missed": 5, "injury": 5,
	"shot": 4, "big_hit": 4, "late_block": 4, "knockdown": 4, "substitution": 4,
	"throw_up": 3, "mishit": 3, "air_shot": 3, "tackle": 3, "cleek": 3, "block": 3,
	"clash": 3, "stick_battle": 3, "shoulder": 3,
	"throw_up_won": 2, "shy": 2, "corner": 2, "hit_out": 2, "control": 2, "slip": 2,
	"filler": 1,
}
## Seconds before a category can be heard again, so the small stuff
## (every tackle, every block) doesn't turn into a running list.
const COOLDOWN := {
	"big_hit": 16.0, "shot": 6.0, "mishit": 15.0, "air_shot": 15.0, "tackle": 14.0,
	"cleek": 14.0, "block": 20.0, "clash": 14.0, "stick_battle": 20.0, "shoulder": 16.0,
	"knockdown": 25.0, "injury": 15.0, "foul": 6.0, "throw_up_won": 30.0, "control": 18.0, "slip": 30.0, "shy": 20.0,
	"hit_out": 20.0, "foul_missed": 20.0, "late_block": 15.0, "filler": 20.0,
}
const QUIET_GAP := 2.5     ## s after a line before priority 3 and under speak again
const FILLER_AFTER := 24.0 ## s of open play with nothing said
const CAPTION_MIN := 2.6   ## s a caption stays up without a voice
const CAPTION_PER_CHAR := 0.045
const BIG_HIT := 34.0      ## yd/s off the caman
const SHOT_RANGE := 55.0   ## yd from the goal it is heading for
const LATE_MINUTE := 80

var m                      ## the match (scripts/match.gd)
var view: Node             ## the match view, for the pre-match check; may be null
## Off, captions, voice or both: Game.commentary (0 both, 1 captions, 2 voice, 3 off).
var captions := true
var voice := true

var lines := {}            ## category -> Array of line texts
var said: Array = []       ## everything said: {cat, id, text, at, voiced}, for the tests
var caption := ""
var line_id := ""
var player: AudioStreamPlayer

var _bags := {}            ## category -> indices not yet used this round
var _last_said := {}       ## category -> time
var _t := 0.0
var _busy_until := 0.0
var _caption_from := 0.0
var _caption_until := 0.0
var _priority := 0
var _quiet_since := 0.0
var _next_event := 0
var _next_post := 0
var _next_call := 0
var _next_card := 0
var _last_kind := ""
var _last_team := -1
var _shot_team := -1
var _shot_at := -100.0
var _started := false
var _after_break := false
var _voices := {}          ## id -> AudioStream or null, looked up once


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player = AudioStreamPlayer.new()
	player.volume_db = 2.0
	add_child(player)
	lines = load_lines()
	var game := get_node_or_null("/root/Game")
	if game != null and game.get("commentary") != null:
		set_mode(int(game.commentary))
	if m != null:
		_skip_history()


## 0 captions and voice, 1 captions only, 2 voice only, 3 off.
func set_mode(mode: int) -> void:
	captions = mode == 0 or mode == 1
	voice = mode == 0 or mode == 2


## Start from now: whatever the match did before we were added is old news,
## unless it is only the opening throw-up.
func _skip_history() -> void:
	if m.half == 1 and m.clock <= 0.0:
		return
	_next_event = m.events.size()
	_next_post = m.ball_sim.post_hits.size()
	_next_call = m.referee.calls.size()
	_next_card = m.referee.cards.size()
	_started = _next_event > 0


static func load_lines() -> Dictionary:
	var f := FileAccess.open(LINES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("lines")) != TYPE_DICTIONARY:
		return {}
	return data["lines"]


## The voice file name for a line: category_01 for the first line in a list.
static func line_id_for(cat: String, index: int) -> String:
	return "%s_%02d" % [cat, index + 1]


func _process(delta: float) -> void:
	if m == null:
		return
	if not m.paused:
		_t += delta
	visible = captions and not (view != null and view.get("prematch") != null)
	var game_over: bool = m.state == m.State.FULL_TIME
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		_on_event(e)
	var posts: Array = m.ball_sim.post_hits
	if _next_post < posts.size():
		_next_post = posts.size()
		say("post")
	var calls: Array = m.referee.calls
	while _next_call < calls.size():
		_on_call(calls[_next_call])
		_next_call += 1
	var cards: Array = m.referee.cards
	while _next_card < cards.size():
		var c: Dictionary = cards[_next_card]
		_next_card += 1
		say("red_card" if c["colour"] == "red" else "yellow_card")
	if not game_over and m.state == m.State.PLAY and not m.paused and _t - _quiet_since > FILLER_AFTER and _t > _busy_until:
		say("filler")
	if _t > _busy_until:
		_priority = 0
	queue_redraw()


func _on_event(e: Dictionary) -> void:
	var team: int = e.get("team", -1)
	match e["type"]:
		"throw_up":
			if not _started:
				say("match_start")
			elif _after_break:
				say("second_half")
			else:
				say("throw_up")
			_started = true
			_after_break = false
		"throw_up_won":
			say("throw_up_won")
		"hit":
			_last_kind = e.get("kind", "")
			_last_team = team
			if _last_kind == "fresh_air":
				say("air_shot")
		"strike":
			_on_strike(e)
		"save":
			say("save")
		"goal":
			var score: Array = m.score
			if score[0] == score[1]:
				say("goal_equaliser")
			elif e.get("half", 1) >= 2 and m.match_minute() >= LATE_MINUTE:
				say("goal_late")
			else:
				say("goal")
		"Hit-out":
			# The defending side gets the hit-out: wide, if the other lot just shot.
			say("wide" if _shot_team == 1 - team and _t - _shot_at < 6.0 else "hit_out")
		"Shy":
			say("shy")
		"Corner":
			say("corner")
		"tackle":
			if e.get("won", false):
				say("tackle")
		"battle":
			say("stick_battle")
		"clash":
			say("clash")
		"cleek":
			say("cleek")
		"block", "stick_block", "body_stop":
			say("block")
		"late_block":
			say("late_block")
		"air_kill":
			say("control")
		"barge":
			if not e.get("in_the_back", false):
				say("shoulder")
		"knockdown":
			say("knockdown")
		"slip":
			say("slip")
		"injury":
			say("injury")
		"substitution":
			say("substitution")
		"shootout":
			say("shootout_start")
		"shootout_kick":
			say("shootout_score" if e.get("scored", false) else "shootout_miss")
		"half_end":
			_after_break = true
			if m.state == m.State.HALF_TIME:
				say("extra_time" if e.get("half", 1) == 2 else "half_time")
			elif not m.shootout:
				say("full_time")


## A strike: a mishit, a shot at goal or just a big hit.
func _on_strike(e: Dictionary) -> void:
	if _last_kind in ["thin", "heel", "toe"]:
		say("mishit")
		return
	var vel := Vector2(m.ball_vel.x, m.ball_vel.y)
	var speed := vel.length()
	var by = e.get("by")
	if by != null and speed > 12.0:
		var goal: Vector2 = m.target_goal(by.team)
		var to_goal: Vector2 = goal - m.ball_pos
		if to_goal.length() < SHOT_RANGE and vel.normalized().dot(to_goal.normalized()) > 0.93:
			_shot_team = by.team
			_shot_at = _t
			say("shot")
			return
	if speed >= BIG_HIT:
		say("big_hit")


func _on_call(c: Dictionary) -> void:
	match c.get("call", ""):
		"free hit":
			say("foul")
		"penalty":
			say("penalty")
		"offside":
			say("offside")
		"missed":
			say("foul_missed")
		"no goal":
			say("no_goal")


## Say a line from `cat`, if nothing more important is being said. Returns
## whether it was said.
func say(cat: String) -> bool:
	var pool: Array = lines.get(cat, [])
	if pool.is_empty():
		return false
	var prio: int = PRIORITY.get(cat, 1)
	if _t < _busy_until and prio <= _priority:
		return false
	if prio <= 3 and _t - _quiet_since < QUIET_GAP:
		return false
	if _t - float(_last_said.get(cat, -1000.0)) < COOLDOWN.get(cat, 0.0):
		return false
	var index := _draw_from(cat, pool.size())
	var text: String = pool[index]
	var id := line_id_for(cat, index)
	_last_said[cat] = _t
	_priority = prio
	caption = text
	line_id = id
	var length: float = max(CAPTION_MIN, text.length() * CAPTION_PER_CHAR + 1.2)
	var stream: AudioStream = _voice(id) if voice else null
	if stream != null:
		player.stream = stream
		player.play()
		length = max(length, stream.get_length() + 0.4)
	elif voice and not captions:
		length = 0.0  # nothing to say it with
	_caption_from = _t
	_caption_until = _t + length
	_busy_until = _t + length
	_quiet_since = _busy_until
	said.append({"cat": cat, "id": id, "text": text, "at": _t, "voiced": stream != null})
	return true


## Shuffle-bag: every line in a category is used once before any repeats.
func _draw_from(cat: String, n: int) -> int:
	var bag: Array = _bags.get(cat, [])
	if bag.is_empty() or bag.size() > n:
		bag = range(n)
		bag.shuffle()
		_bags[cat] = bag
	return bag.pop_back()


## The recording for a line, if there is one.
func _voice(id: String) -> AudioStream:
	if _voices.has(id):
		return _voices[id]
	var stream: AudioStream = null
	for dir in VOICE_DIRS:
		for ext in VOICE_EXTS:
			var path: String = dir + id + "." + ext
			if dir.begins_with("res://"):
				if ResourceLoader.exists(path):
					stream = load(path)
			elif FileAccess.file_exists(path):
				stream = _load_loose(path, ext)
			if stream != null:
				break
		if stream != null:
			break
	_voices[id] = stream
	return stream


static func _load_loose(path: String, ext: String) -> AudioStream:
	match ext:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


## The caption, top centre under the score bug: a dark slanted panel with a
## gold mic tag, fading in and out.
func _draw() -> void:
	if caption == "" or _t > _caption_until + 0.3:
		return
	var fade := clampf((_caption_until + 0.3 - _t) / 0.3, 0.0, 1.0) * clampf((_t - _caption_from) / 0.15, 0.0, 1.0)
	if fade <= 0.0:
		return
	var screen := get_viewport_rect().size
	var bold := ShintyStyle.font("bold")
	var black := ShintyStyle.font("black")
	var size := 22
	var max_w := minf(screen.x - 120.0, 760.0)
	while size > 15 and bold.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w - 70.0:
		size -= 1
	var tw := bold.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := minf(tw + 76.0, max_w)
	var r := Rect2(Vector2((screen.x - w) / 2.0, 74.0), Vector2(w, 38.0))
	draw_style_box(ShintyStyle.box(Color(0.04, 0.06, 0.08, 0.86 * fade), ShintyStyle.SLANT), r)
	draw_style_box(ShintyStyle.box(Color(ShintyStyle.GOLD, fade), ShintyStyle.SLANT), Rect2(r.position + Vector2(8, 8), Vector2(34, 22)))
	_draw_mic(r.position + Vector2(25, 19), Color(ShintyStyle.GOLD_DARK, fade))
	draw_string(bold, r.position + Vector2(54, 27), caption, HORIZONTAL_ALIGNMENT_LEFT, w - 64.0, size, Color(1, 1, 1, fade))


func _draw_mic(c: Vector2, col: Color) -> void:
	draw_rect(Rect2(c + Vector2(-3, -9), Vector2(6, 6)), col)
	draw_circle(c + Vector2(0, -9), 3.0, col)
	draw_circle(c + Vector2(0, -3), 3.0, col)
	draw_arc(c + Vector2(0, -4), 6.0, 0.15, PI - 0.15, 12, col, 1.6)
	draw_line(c + Vector2(0, 2), c + Vector2(0, 6), col, 1.6)
	draw_line(c + Vector2(-4, 6), c + Vector2(4, 6), col, 1.6)
