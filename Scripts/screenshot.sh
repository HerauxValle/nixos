#!/usr/bin/env bash

BASE="$HOME/Pictures/Screenshots"

DO_CLIP=false
DO_SAVE=false

for arg in "$@"; do
  [ "$arg" = "--clipboard" ] && DO_CLIP=true
  [ "$arg" = "--save" ] && DO_SAVE=true
done

# default = clipboard
if ! $DO_CLIP && ! $DO_SAVE; then
  DO_CLIP=true
fi

YEAR=$(date +"%Y")
MONTH_NUM=$(date +"%m")
MONTH_NAME=$(date +"%B")
DAY_NUM=$(date +"%d")
DAY_NAME=$(date +"%A")
TIME=$(date +"%H-%M-%S")

DIR="$BASE/$YEAR/$MONTH_NUM-$MONTH_NAME/$DAY_NUM-$DAY_NAME"
FILE="$DIR/$TIME.png"

mkdir -p "$DIR"

TMP="/tmp/screenshot_$TIME.png"

# capture region (stable method)
grim -g "$(slurp)" "$TMP"

# if failed
[ ! -s "$TMP" ] && exit 1

# clipboard
$DO_CLIP && wl-copy < "$TMP"

# save
$DO_SAVE && mv "$TMP" "$FILE" || rm "$TMP"