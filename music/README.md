# Menu music

`playlist.json` lists the menu tracks. The game (`scripts/music.gd`, autoload
`Music`) shuffles them and crossfades from one to the next on the menu and
loading screens, and fades out when a match starts. The volume is the
**Music** setting on the Controls screen.

## The mp3s are not in git

The repository is public and these tracks are not cleared for release, so
`music/*.mp3` is gitignored. To hear them, copy the mp3s into this folder
(the names in `playlist.json`) and open the project in Godot. A track whose
file is missing is skipped; with none present the menu is silent.

## Demo-only flag

Every track with `"demo_only": true` (or `"licensed": false`):

- plays only in the editor, or in a build exported with the custom feature
  `demo` (Export > preset > Features > Custom: `demo`);
- is left out of every other export by `addons/demo_music/` (an export plugin),
  so a release build can't ship it by accident.

Before a Steam release, replace these with licensed tracks and set
`licensed: true` and `demo_only: false`.
