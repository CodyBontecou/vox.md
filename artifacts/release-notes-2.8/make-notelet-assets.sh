#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$ROOT/videos"
OUTPUT="$ROOT/notelet"
mkdir -p "$OUTPUT"

scale_filter="scale=720:720:in_range=pc:out_range=tv:in_color_matrix=bt470bg:out_color_matrix=bt709:flags=lanczos,format=yuv420p"
codec_options=(
  -an
  -c:v libx264
  -profile:v main
  -level:v 3.1
  -preset slow
  -crf 22
  -pix_fmt yuv420p
  -color_range tv
  -colorspace bt709
  -movflags +faststart
)

encode() {
  local source="$1"
  local crop_filter="$2"
  local destination="$3"

  ffmpeg -y -loglevel error \
    -i "$INPUT/$source" \
    -vf "$crop_filter,$scale_filter" \
    "${codec_options[@]}" \
    "$OUTPUT/$destination"
}

encode \
  "01-preset-quick-access.mp4" \
  "crop=1206:1206:0:900" \
  "01-preset-quick-access-square.mp4"

encode \
  "02-task-send-undo.mp4" \
  "crop=1206:1206:0:200" \
  "02-task-send-undo-square.mp4"

# Follow the setting being changed, then settle on the right-side preset rail.
encode \
  "03-capture-bar-options.mp4" \
  "crop=1206:1206:0:'if(lt(t,2.2),250,if(lt(t,5.6),250+(t-2.2)*1050/3.4,1300))'" \
  "03-capture-bar-options-square.mp4"

# Shift down while the recording-help sheet is open.
encode \
  "04-recording-controls.mp4" \
  "crop=1206:1206:0:'if(lt(t,4.2),950,if(lt(t,6.6),1300,1000))'" \
  "04-recording-controls-square.mp4"

encode \
  "05-image-alt-text.mp4" \
  "crop=1206:1206:0:1050" \
  "05-image-alt-text-square.mp4"

encode \
  "06-audio-filename-template.mp4" \
  "crop=1206:1206:0:1150" \
  "06-audio-filename-template-square.mp4"

for video in "$OUTPUT"/*.mp4; do
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,profile,width,height,pix_fmt,color_range,color_space,r_frame_rate \
    -show_entries format=duration,size \
    -of json \
    "$video" >/dev/null
done
