# Commentary voice files

The match commentary (`broadcast/commentary.gd`) picks a line from
`data/commentary.json` when something happens: a goal, a save, a big hit, a
foul, half time and so on. It always shows the line as a caption, top centre
under the score bug. If a recording of that line exists, it plays it as well.
Players choose captions, voice, both or neither under Settings > Commentary.

The lines are all original, written for ProShinty: generic Scots-flavoured
patter with no player or team names, so one recording fits every match. No
real commentator's name, catchphrase or voice is used.

## File names

Each line's id is `<category>_<nn>`, where `nn` is its place in the category's
list counting from 01. `goal_01` is the first goal line, "GOAL! Oh, ya beauty!".
The game looks for, in this order:

1. `user://commentary/<id>.ogg`, `.mp3` or `.wav`. These are loose files, so you
   can try a recording without re-importing anything. On Windows that folder is
   `%APPDATA%\Godot\app_userdata\Shinty\commentary`.
2. `res://audio/commentary/<id>.ogg`, `.mp3` or `.wav` (this folder). These ship
   with the game; Godot imports them when the editor opens.

A line without a file just shows as a caption.

Club and ground names are recorded on their own, spelt the way they should
sound (`"teams"` and `"grounds"` in `data/commentary.json`): `team_kingussie`
says "King-YOO-see", `ground_portree` says "Port-REE". Captions show the real
spelling. A line with `{home}`, `{away}` or `{ground}` in it, like the intro
("This is Dougal Glenorchy, your commentator for another great game of shinty
between {home} and {away} at the beautiful {ground}"), is recorded in pieces:
`intro_01_a` is the text before the first name, `intro_01_b` the next bit, and
so on. The game plays the pieces and the names one after another, and only if
every piece is recorded. After a goal the commentator names the scorers with
their `team_` clip.

If a name comes out wrong, change its spelling in the json and record it
again (`--only team` or `--only ground`).

Add new lines to the end of a category's list and never reorder one, or ids
will point at the wrong recordings. If you change a line's text, record it
again: `status` below lists the stale ones.

## Making the recordings

`tools/commentary_voice.py` does it:

```sh
python3 tools/commentary_voice.py list lines.csv     # every id and line, for any TTS service
python3 tools/commentary_voice.py status             # what's recorded, stale or orphaned
ELEVENLABS_API_KEY=... python3 tools/commentary_voice.py elevenlabs <voice id>
```

The `elevenlabs` command records every line that has no file yet, or whose
text has changed, as `<id>.mp3` here, and keeps `manifest.json` (id to the text
recorded). Use `--only goal` for one category, or `--all` to redo everything.
A full run is about 490 clips (lines plus 37 clubs and 4 grounds) and
roughly 13,700 characters.

Which voice to use:

- Use a text-to-speech plan whose terms allow commercial use in a game. For
  ElevenLabs that means a paid plan; the free tier is non-commercial.
- Use a stock voice from the provider's library that is licensed for
  commercial use, or one made with its voice-design tool. A Scottish accent
  suits the lines best. Don't clone or imitate a real commentator.
- Keep the plan's licence terms, or a screenshot of them, with the project.
- Listen to a sample from each category before recording everything. The Scots
  spellings ("no'", "deid", "canny"; "-nae" is spelt "-nay", which reads better) read well with a Scottish voice;
  if one comes out wrong, re-spell it in the json and record that line again.

## Steam

Steam asks whether a game uses AI-generated content. These lines were written
with an AI assistant, and the voice will come from AI text-to-speech, so tick
the box for **pre-generated** AI content. Describe it on the store page, for
example: "Match commentary lines were written with AI assistance and voiced
with AI text-to-speech; all were reviewed before release." Everything is
generated before release, so the extra questions about content generated live
during play don't apply.
