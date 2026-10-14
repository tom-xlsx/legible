#!/bin/bash
# Turns a screen recording into a small looping GIF for the README.
#   scripts/gif.sh "in.mov" docs/out.gif [WIDTH=720] [SPEED=2] [FPS=10]
# WIDTH is the GIF's pixel width, SPEED the playback multiplier (2 = twice as fast).
# CROP=w:h:x:y (source pixels) trims the desktop around the window; CROP=auto
# detects it from the dark surround.
set -euo pipefail
IN="$1"; OUT="$2"; WIDTH="${3:-720}"; SPEED="${4:-2}"; FPS="${5:-10}"
command -v ffmpeg >/dev/null || { echo "gif: ffmpeg is needed (brew install ffmpeg)" >&2; exit 1; }
if [ "${CROP:-}" = "auto" ]; then
  CROP="$(ffmpeg -v info -ss 3 -t 2 -i "$IN" -vf "cropdetect=limit=24:round=2:reset=0" -f null - 2>&1 \
    | grep -o 'crop=[0-9:]*' | tail -1 | cut -d= -f2)"
  echo "gif: cropping to $CROP"
fi
filters="${CROP:+crop=$CROP,}setpts=PTS/$SPEED,fps=$FPS,scale=$WIDTH:-2:flags=lanczos"
ffmpeg -v error -y -i "$IN" \
  -vf "$filters,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$OUT"
printf '%s: %s, %s frames\n' "$OUT" "$(du -h "$OUT" | cut -f1)" "$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$OUT")"
