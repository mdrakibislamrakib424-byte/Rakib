#!/usr/bin/env bash
# Arranges the downloaded asset pack (a zip with all files mixed together)
# into the Godot project folders. Run by the GitHub workflow before the export.
#
#   bash tools/setup_assets.sh <pack.zip> [project_dir]
#
# Result (inside the project):
#   assets/textures/                 ambientCG textures (Road007, Grass001, ...)
#   assets/sky/                      HDR skies
#   assets/audio/ambient/            wind + meadow loops (.wav)
#   assets/audio/music/              background music (.mp3)
#   assets/models/<name>/            one folder per gltf model (+ its .bin and textures)
#   assets/models/props/             guardrail.glb, road_signs.glb, street_lamp.glb
set -euo pipefail

PACK_ZIP="${1:?usage: setup_assets.sh <pack.zip> [project_dir]}"
PROJECT="${2:-.}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TEX_DIR="$PROJECT/assets/textures"
SKY_DIR="$PROJECT/assets/sky"
AMB_DIR="$PROJECT/assets/audio/ambient"
MUS_DIR="$PROJECT/assets/audio/music"
MODEL_DIR="$PROJECT/assets/models"
PROP_DIR="$MODEL_DIR/props"
mkdir -p "$TEX_DIR" "$SKY_DIR" "$AMB_DIR" "$MUS_DIR" "$MODEL_DIR" "$PROP_DIR"

echo "Unpacking $PACK_ZIP ..."
unzip -q -o "$PACK_ZIP" -d "$TMP"

# 1) glTF models: every model gets its own folder with its .bin and textures.
#    The texture path inside the .gltf is flattened ("textures/x.jpg" -> "x.jpg").
while IFS= read -r -d '' gltf; do
  file_name="$(basename "$gltf")"
  base="${file_name%_[0-9]*k.gltf}"
  dest="$MODEL_DIR/$base"
  mkdir -p "$dest"
  find "$TMP" -type f -name "${base}*" -exec mv -f {} "$dest"/ \;
  sed -i 's#textures/##g' "$dest"/*.gltf
  echo "model: $base -> $(ls "$dest" | wc -l) files"
done < <(find "$TMP" -type f -name '*.gltf' -print0)

# 2) Everything else, by type.
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  case "$name" in
    Road007.png) ;;                                   # preview picture, not needed
    Road007_*|Grass001_*|Ground037_*|Rock063_*|Concrete033_*) mv -f "$f" "$TEX_DIR"/ ;;
    *.hdr) mv -f "$f" "$SKY_DIR"/ ;;
    *.wav) mv -f "$f" "$AMB_DIR"/ ;;
    *.mp3|*.ogg) mv -f "$f" "$MUS_DIR"/ ;;
    guardrail.glb|road_signs.glb|street_lamp.glb) mv -f "$f" "$PROP_DIR"/ ;;
    *) echo "WARNING: not placed anywhere: $name" ;;
  esac
done < <(find "$TMP" -type f -print0)

# 3) Safety check: every file a .gltf points to must exist, otherwise fail early.
missing=0
for gltf in "$MODEL_DIR"/*/*.gltf; do
  dir="$(dirname "$gltf")"
  while IFS= read -r uri; do
    if [ ! -f "$dir/$uri" ]; then
      echo "MISSING: $dir/$uri (needed by $(basename "$gltf"))"
      missing=1
    fi
  done < <(grep -o '"uri" *: *"[^"]*"' "$gltf" | sed 's/.*: *"\(.*\)"/\1/')
done
if [ "$missing" -ne 0 ]; then
  echo "Asset pack is incomplete."
  exit 1
fi
echo "Assets arranged OK."
