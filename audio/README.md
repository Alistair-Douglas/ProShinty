# Match sound

`match_audio.gd` (ShintyMatchAudio) plays the match sound. The match view adds
it as a child; it reads the events the match appends to `match.events`:

| Event | Sound |
|---|---|
| strike | thwack, louder and sharper the harder the ball is hit; duller for a mishit |
| touch | soft tap of ball on stick (not for a keeper's hands) |
| clash, block, stick_block, cleek, late_block | caman-on-caman clack |
| save | tap and a crowd "ooh" |
| goal | crowd cheer (one of two) |

A quiet crowd murmur loops under the whole match and pauses with the game.

## Where the sounds come from

Every file in `sfx/` is synthesised from scratch by `make_sounds.py` (no
recordings or samples), so they carry no third-party licence. They are released
under CC0 1.0 (public domain dedication), like the script that makes them.
To change a sound, edit the script and re-run it:

    python3 -m pip install numpy scipy
    python3 audio/make_sounds.py

`crowd_loop.wav` is imported as a forward loop (see its `.import` file).
Replacing any file with a real recording under the same name also works;
record its licence here if you do.
