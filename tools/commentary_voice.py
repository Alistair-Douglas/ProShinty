#!/usr/bin/env python3
"""Voice files for the match commentary (data/commentary.json).

Every line has an id, <category>_<nn> (nn its place in its list, from 01), and
the game plays audio/commentary/<id>.ogg, .mp3 or .wav when that line comes up.
See audio/commentary/README.md.

  python3 tools/commentary_voice.py list [lines.csv]
      Writes every line as id,text (CSV) for any text-to-speech service.
  python3 tools/commentary_voice.py status
      How many lines have a voice file, and which files are stale (the line's
      text changed since it was recorded) or orphaned.
  ELEVENLABS_API_KEY=... python3 tools/commentary_voice.py elevenlabs VOICE_ID [--all] [--only CATEGORY]
      Records the missing and stale lines with ElevenLabs (needs a paid plan
      for commercial use) as mp3 into audio/commentary/, and notes what each
      file says in audio/commentary/manifest.json. --only team and --only
      ground record the club and ground names (spelt as they should sound).

  python3 tools/commentary_voice.py import FILE ID [FILE ID ...]
      Turns your own recordings (any format ffmpeg reads, e.g. a phone's
      .m4a) into audio/commentary/<id>.ogg: mono, silence trimmed off both
      ends, levelled so every line plays at the same loudness. Needs ffmpeg.

Standard library only.
"""
import csv
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINES = os.path.join(ROOT, "data", "commentary.json")
OUT = os.path.join(ROOT, "audio", "commentary")
MANIFEST = os.path.join(OUT, "manifest.json")
EXTS = (".ogg", ".mp3", ".wav")


def lines():
    with open(LINES, encoding="utf-8") as f:
        data = json.load(f)
    for cat, pool in data["lines"].items():
        for i, text in enumerate(pool):
            id_ = "%s_%02d" % (cat, i + 1)
            if "{" not in text:
                yield id_, cat, text
                continue
            # {home}, {away}, {ground}: the bits between are recorded on their own
            pieces = [p.strip() for p in re.split(r"\{(?:home|away|ground)\}", text) if p.strip()]
            for n, piece in enumerate(pieces):
                yield "%s_%s" % (id_, chr(97 + n)), cat, piece
    # club and ground names, spelt as they should sound
    for club, text in data.get("teams", {}).items():
        yield "team_" + club, "team", text
    for venue, ground in data.get("grounds", {}).items():
        yield "ground_" + venue, "ground", ground["say"]


def manifest():
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            return json.load(f)
    return {}


def voiced(id_):
    return any(os.path.exists(os.path.join(OUT, id_ + e)) for e in EXTS)


def cmd_list(args):
    out = open(args[0], "w", newline="", encoding="utf-8") if args else sys.stdout
    w = csv.writer(out)
    w.writerow(["id", "text"])
    for id_, _, text in lines():
        w.writerow([id_, text])


def cmd_status(_args):
    man = manifest()
    all_lines = list(lines())
    have = [l for l in all_lines if voiced(l[0])]
    stale = [l for l in have if man.get(l[0]) not in (None, l[2])]
    ids = {l[0] for l in all_lines}
    orphans = sorted(f for f in os.listdir(OUT) if f.endswith(EXTS) and os.path.splitext(f)[0] not in ids)
    print("%d of %d lines voiced" % (len(have), len(all_lines)))
    for id_, _, text in stale:
        print("stale: %s (now: %s)" % (id_, text))
    for f in orphans:
        print("orphan: %s" % f)


def cmd_elevenlabs(args):
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not args or not key:
        sys.exit("usage: ELEVENLABS_API_KEY=... commentary_voice.py elevenlabs VOICE_ID [--all] [--only CATEGORY]")
    voice = args[0]
    redo = "--all" in args
    only = args[args.index("--only") + 1] if "--only" in args else None
    model = os.environ.get("ELEVENLABS_MODEL", "eleven_multilingual_v2")
    man = manifest()
    made = 0
    for id_, cat, text in lines():
        if only and cat != only:
            continue
        if not redo and voiced(id_) and man.get(id_, text) == text:
            continue
        body = json.dumps({
            "text": text,
            "model_id": model,
            # lively but steady: a commentator, not an actor
            "voice_settings": {"stability": 0.4, "similarity_boost": 0.8, "style": 0.35},
        }).encode()
        req = urllib.request.Request(
            "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_128" % voice,
            data=body, headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                audio = r.read()
        except urllib.error.HTTPError as e:
            sys.exit("%s: ElevenLabs said %d: %s" % (id_, e.code, e.read()[:300].decode(errors="replace")))
        for e in EXTS:   # one file per line
            old = os.path.join(OUT, id_ + e)
            if os.path.exists(old):
                os.remove(old)
        with open(os.path.join(OUT, id_ + ".mp3"), "wb") as f:
            f.write(audio)
        man[id_] = text
        with open(MANIFEST, "w", encoding="utf-8") as f:
            json.dump(man, f, indent=1, sort_keys=True, ensure_ascii=False)
        made += 1
        print("%s: %s" % (id_, text))
        time.sleep(0.3)
    print("recorded %d lines" % made)


# Trim the silence off each end (the reverse trims the tail), then level to
# the same loudness with a little headroom.
TRIM = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.04"
LEVEL = "highpass=f=70,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100,alimiter=limit=0.8:level=false"


def cmd_import(args):
    if not args or len(args) % 2:
        sys.exit("usage: commentary_voice.py import FILE ID [FILE ID ...]")
    known = {l[0]: l[2] for l in lines()}
    man = manifest()
    for src, id_ in zip(args[::2], args[1::2]):
        if id_ not in known:
            sys.exit("%s: no line has that id (see: commentary_voice.py list)" % id_)
        for e in EXTS:
            old = os.path.join(OUT, id_ + e)
            if os.path.exists(old):
                os.remove(old)
        out = os.path.join(OUT, id_ + ".ogg")
        filt = ",".join([TRIM, "areverse", TRIM, "areverse", LEVEL])
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
                        "-af", filt, "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", out],
                       check=True)
        man[id_] = known[id_]
        print("%s -> %s: %s" % (os.path.basename(src), id_, known[id_]))
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True, ensure_ascii=False)


if __name__ == "__main__":
    cmds = {"list": cmd_list, "status": cmd_status, "elevenlabs": cmd_elevenlabs, "import": cmd_import}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    os.makedirs(OUT, exist_ok=True)
    cmds[sys.argv[1]](sys.argv[2:])
