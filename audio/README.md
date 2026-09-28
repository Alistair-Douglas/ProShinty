# Match sound

`match_audio.gd` (ShintyMatchAudio) plays the match sound. The match view adds
it as a child; it reads the events the match appends to `match.events`, and
hits off the posts or bar from `match.ball_sim.post_hits`:

| What happens | Sound |
|---|---|
| strike | `hit_hockey.wav`, louder and sharper the harder the ball is hit; duller for a mishit |
| touch, save | `hit_hockey.wav`, quiet (not for a keeper's hands) |
| ball off a post or the bar | `post_bat.mp3`, louder the harder it hits; a hard one gets the crowd's "ooh" |
| clash, block, stick_block, cleek, late_block | `clack_plank.wav` |
| save | `ooh_crowd.wav` from the crowd |
| goal | `cheer_crowd.wav` |

A quiet crowd murmur (`crowd_loop.wav`) loops under the whole match and pauses
with the game.

## Where the sounds come from

Recordings from [Freesound](https://freesound.org), chosen by Alistair. Trimmed
to the hit (the cheer without its quiet start, the moan to its first two and a
half seconds) and mixed to mono; `post_bat.mp3` is as downloaded. Check each licence on its Freesound page before release, and
credit the authors in the game if it asks for attribution:

| File | Freesound sound | Author |
|---|---|---|
| `hit_hockey.wav` | [#266647 "hit hockey"](https://freesound.org/s/266647/) | eelke |
| `cheer_crowd.wav` | [#863035 "small audience cheer"](https://freesound.org/s/863035/) | robo9418 |
| `post_bat.mp3` | [#851452 "bat_hit2"](https://freesound.org/s/851452/) | hashtagsmcgee |
| `ooh_crowd.wav` | [#150969 "crowd moaning"](https://freesound.org/s/150969/) | unchaz |
| `clack_plank.wav` | [#366190 "plank falling"](https://freesound.org/s/366190/) | twiggie2000 |

`crowd_loop.wav` is synthesised from scratch by `make_sounds.py` and released
CC0. To rebuild it:

    python3 -m pip install numpy scipy
    python3 audio/make_sounds.py

`crowd_loop.wav` is imported as a forward loop (see its `.import` file).
Any file can be replaced by another recording with the same name; update the
table above when you do.
