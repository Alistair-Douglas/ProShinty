# Menu music

`playlist.json` lists the menu tracks. The game (`scripts/music.gd`, autoload
`Music`) shuffles them and crossfades from one to the next on the menu and
loading screens, and fades out when a match starts. The volume is the
**Music** setting on the Controls screen.

## CC0 tracks (in git)

`cc0/` holds seven tracks Alistair supplied as CC0 (2026-10-04). They are
committed and ship in every build. Two files carry a licence tag that agrees
(section31: "No Copyright, free to do whatever you want with it",
sdacfn: "This work is marked CC0 1.0"); the five Play House tracks have no
licence tag, so their CC0 status is as stated by Alistair. Each entry in
`playlist.json` records this under `licence_source`.

## The Epidemic Sound mp3s are not in git

The repository is public and these tracks are not cleared for release, so
`music/*.mp3` is gitignored. To hear them, copy the mp3s into this folder
and open the project in Godot. Any file name works: an mp3/ogg/wav that
isn't named in `playlist.json` still plays, and counts as demo only. With no
files present the menu is silent (the output log says so).

## Demo-only flag

Every track with `"demo_only": true` (or `"licensed": false`):

- plays only in the editor, or in a build exported with the custom feature
  `demo` (Export > preset > Features > Custom: `demo`);
- is left out of every other export by `addons/demo_music/` (an export plugin),
  so a release build can't ship it by accident.

Before a Steam release, replace these with licensed tracks and set
`licensed: true` and `demo_only: false`.
