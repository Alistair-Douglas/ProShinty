class_name ShintyMatchAudio
extends Node
## Match sound: the thwack of caman on ball, the ball off the post or bar,
## stick clashes, the crowd's murmur, its "ooh" at a save and its roar for a goal. Everything is driven by the
## events the match appends to match.events, so the match itself knows nothing
## about sound. Where each sound comes from is in audio/README.md.

const HIT := preload("res://audio/sfx/hit_hockey.wav")
const POST := preload("res://audio/sfx/post_bat.mp3")
const CLACK := preload("res://audio/sfx/clack_plank.wav")
const CHEER := preload("res://audio/sfx/cheer_crowd.wav")
const OOH := preload("res://audio/sfx/ooh_crowd.wav")
const CROWD_LOOP := preload("res://audio/sfx/crowd_loop.wav")

const SOFT_HIT := 8.0      ## yd/s: a strike this slow is the quietest thwack
const HARD_HIT := 40.0     ## yd/s: a strike this fast is the loudest
const CROWD_DB := -16.0    ## background murmur level
const VOICES := 8          ## sound effects that can overlap

var m                      # the match (scripts/match.gd); defaults to the parent
var crowd: AudioStreamPlayer
var roar: AudioStreamPlayer  # cheers and oohs, one at a time
var _sfx: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _next_event := 0
var _next_post := 0
var _last_kind := ""
var heard := {}            # plays per sound file, for the tests


func _ready() -> void:
	if m == null:
		m = get_parent()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	roar = AudioStreamPlayer.new()
	add_child(roar)
	crowd = AudioStreamPlayer.new()
	crowd.stream = CROWD_LOOP
	crowd.volume_db = CROWD_DB
	add_child(crowd)
	crowd.play()
	_next_event = m.events.size()
	_next_post = m.ball_sim.post_hits.size()


func _process(_delta: float) -> void:
	crowd.stream_paused = m.paused
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		_on_event(e)
	var posts: Array = m.ball_sim.post_hits
	while _next_post < posts.size():
		off_the_post(posts[_next_post])
		_next_post += 1


func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"hit":
			_last_kind = e.get("kind", "")
		"strike":
			strike(Vector2(m.ball_vel.x, m.ball_vel.y).length(), _last_kind)
		"touch":
			if not e.get("hands", false):
				play(HIT, randf_range(-17.0, -12.0), randf_range(1.1, 1.25))  # a soft touch
		"clash", "stick_block", "cleek", "block", "late_block":
			play(CLACK, -4.0, randf_range(0.93, 1.07))
		"save":
			play(HIT, -10.0, 0.8)
			crowd_react(OOH, -5.0)
		"goal":
			crowd_react(CHEER, 0.0)


## The thwack: louder, sharper and a touch higher the harder the ball is hit.
## A mishit (thin, heel, toe) sounds duller.
func strike(speed: float, kind: String = "") -> void:
	var s := clampf(inverse_lerp(SOFT_HIT, HARD_HIT, speed), 0.0, 1.0)
	var db := lerpf(-13.0, 0.0, s)
	var pitch := lerpf(0.86, 1.1, s) * randf_range(0.97, 1.03)
	if kind in ["thin", "heel", "toe"]:
		db -= 4.0
		pitch *= 0.88
	play(HIT, db, pitch)
	heard["strike"] = heard.get("strike", 0) + 1


## The ball cracking off a post or the bar, louder the harder it hits;
## a hard one gets an "ooh" from the crowd.
func off_the_post(speed_ms: float) -> void:
	var s := clampf(inverse_lerp(2.0, 25.0, speed_ms), 0.0, 1.0)
	play(POST, lerpf(-12.0, 0.0, s), randf_range(0.95, 1.05))
	if s > 0.4:
		crowd_react(OOH, -5.0)


func crowd_react(stream: AudioStream, db: float) -> void:
	# a goal always gets its roar; an ooh does not cut a roar short
	if roar.playing and roar.stream != OOH and stream == OOH:
		return
	roar.stream = stream
	roar.volume_db = db
	roar.play()
	_count(stream)


func play(stream: AudioStream, db: float, pitch: float = 1.0) -> AudioStreamPlayer:
	var p := _sfx[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	_count(stream)
	return p


func _count(stream: AudioStream) -> void:
	var key := stream.resource_path.get_file().get_basename()
	heard[key] = heard.get(key, 0) + 1
