#!/usr/bin/env bash
# Runs the headless test suite. Used by CI (.github/workflows/tests.yml) and
# locally: GODOT=/path/to/godot tests/run_all.sh [quick]
# A test fails if it exits non-zero or Godot reports a script error.
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
QUICK="${1:-}"
OUT="${TMPDIR:-/tmp}/shinty-tests"
mkdir -p "$OUT"
failed=()

run() {
	local name="$1"; shift
	echo "::group::$name"
	local log="$OUT/$name.log"
	"$@" 2>&1 | tee "$log"
	local code=${PIPESTATUS[0]}
	echo "::endgroup::"
	if [ "$code" -ne 0 ]; then
		echo "::error::$name exited with $code"
		failed+=("$name")
	elif grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
		echo "::error::$name hit a script error"
		grep -E -A2 "SCRIPT ERROR|Parse Error|Failed to load script" "$log" | head -40
		failed+=("$name")
	fi
}

# Import once so scripts can find the assets and class names.
"$GODOT" --headless --import --path . > "$OUT/import.log" 2>&1 || true

run models   timeout 300  "$GODOT" --headless --path . -s tests/model_test.gd
run stats    timeout 900  "$GODOT" --headless --path . -s tests/stats_test.gd
run kits     timeout 120  "$GODOT" --headless --path . -s tests/kit_test.gd
run camans   timeout 300  "$GODOT" --headless --path . -s tests/caman_test.gd
run practice timeout 600  "$GODOT" --headless --path . -s tests/practice_test.gd
run referee  timeout 300  "$GODOT" --headless --path . -s tests/referee_test.gd
run crowd    timeout 600  "$GODOT" --headless --fixed-fps 60 --path . -s tests/crowd_test.gd
run camera   timeout 1200 "$GODOT" --headless --fixed-fps 60 --path . -s tests/camera_test.gd
run audio    timeout 600  "$GODOT" --headless --path . -s tests/audio_test.gd
run music    timeout 120  "$GODOT" --headless --path . -s tests/music_test.gd
run feel     timeout 600  "$GODOT" --headless --fixed-fps 60 --path . -s tests/feel_test.gd
run subs     timeout 1200 "$GODOT" --headless --path . -s tests/subs_test.gd
run weather  timeout 900  "$GODOT" --headless --path . -s tests/weather_test.gd
run skills   timeout 300  "$GODOT" --headless --path . -s tests/skills_test.gd
run sim      timeout 1200 "$GODOT" --headless --path . -s tests/sim_test.gd
run ratings  timeout 1200 "$GODOT" --headless --path . -s tests/rating_gap_test.gd
run checkpoint timeout 3000 "$GODOT" --headless --fixed-fps 60 --path . -s tests/checkpoint_test.gd -- $QUICK
if command -v xvfb-run > /dev/null; then
	mkdir -p "$OUT/menu"
	run menu timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/menu_test.gd -- "$OUT/menu"
	run subs_screen timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_subs.gd -- "$OUT/menu"
	run foul_replay timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/foul_replay_test.gd -- "$OUT/menu"
fi

if [ ${#failed[@]} -gt 0 ]; then
	echo "Failed: ${failed[*]}"
	exit 1
fi
echo "All tests passed"
