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
| throw-up; shy, corner, hit-out (quieter); free hit, penalty hit (loudest) | `whistle.wav` |
| half time | `whistle_half.wav`, two blasts |
| full time | `whistle_full.wav`, two short blasts and a long one |

Match commentary (captions and voice files) lives in `commentary/`: see
`commentary/README.md`.

The crowd chattering (`crowd_chatter.wav`) loops quietly under the whole match
and pauses with the game.

## Where the sounds come from

Recordings from [Freesound](https://freesound.org), chosen by Alistair. Trimmed
to the hit (the cheer without its quiet start, the moan to its first two and a
half seconds, the chatter to its steadiest 45 seconds with the ends crossfaded
so it loops; the half-time and full-time calls are built from the one whistle
blast, stretched and repeated) and mixed to mono; `post_bat.mp3` is as downloaded. Check each licence on its Freesound page before release, and
credit the authors in the game if it asks for attribution:

| File | Freesound sound | Author |
|---|---|---|
| `hit_hockey.wav` | [#266647 "hit hockey"](https://freesound.org/s/266647/) | eelke |
| `cheer_crowd.wav` | [#863035 "small audience cheer"](https://freesound.org/s/863035/) | robo9418 |
| `post_bat.mp3` | [#851452 "bat_hit2"](https://freesound.org/s/851452/) | hashtagsmcgee |
| `ooh_crowd.wav` | [#150969 "crowd moaning"](https://freesound.org/s/150969/) | unchaz |
| `clack_plank.wav` | [#366190 "plank falling"](https://freesound.org/s/366190/) | twiggie2000 |
| `whistle*.wav` | [#218318 "referee whistle blow gymnasium"](https://freesound.org/s/218318/) | splicesound |
| `crowd_chatter.wav` | [#400588 "crowd speaking chattering talking"](https://freesound.org/s/400588/) | misjoc |

`crowd_chatter.wav` is imported as a forward loop (see its `.import` file).
Any file can be replaced by another recording with the same name; update the
table above when you do.
