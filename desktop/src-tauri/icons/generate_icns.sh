#!/bin/bash
set -e

# Define source and iconset directory
SOURCE="icon_no_bg.png"
ICONSET="icon.iconset"

# Ensure venv exists and install dependencies if needed
if [ ! -d "venv" ]; then
    echo "Creating venv..."
    python3 -m venv venv
    ./venv/bin/pip install Pillow
fi

# Run background removal
echo "Removing background..."
# This might take a moment on first run to download model (~100MB)
./venv/bin/python3 remove_bg.py

if [ ! -f "$SOURCE" ]; then
    echo "Error: Background removal failed, output file not found."
    exit 1
fi

# Ensure clean slate for iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Function to resize
resize() {
    size=$1
    input=$2
    output=$3
    sips -z $size $size -s format png "$input" --out "$output"
}

# Generate all required sizes
echo "Generating icon_512x512@2x.png..."
resize 1024 "$SOURCE" "$ICONSET/icon_512x512@2x.png"

echo "Generating icon_512x512.png..."
resize 512 "$SOURCE" "$ICONSET/icon_512x512.png"

echo "Generating icon_256x256@2x.png..."
resize 512 "$SOURCE" "$ICONSET/icon_256x256@2x.png"

echo "Generating icon_256x256.png..."
resize 256 "$SOURCE" "$ICONSET/icon_256x256.png"

echo "Generating icon_128x128@2x.png..."
resize 256 "$SOURCE" "$ICONSET/icon_128x128@2x.png"

echo "Generating icon_128x128.png..."
resize 128 "$SOURCE" "$ICONSET/icon_128x128.png"

echo "Generating icon_32x32@2x.png..."
resize 64 "$SOURCE" "$ICONSET/icon_32x32@2x.png"

echo "Generating icon_32x32.png..."
resize 32 "$SOURCE" "$ICONSET/icon_32x32.png"

echo "Generating icon_16x16@2x.png..."
resize 32 "$SOURCE" "$ICONSET/icon_16x16@2x.png"

echo "Generating icon_16x16.png..."
resize 16 "$SOURCE" "$ICONSET/icon_16x16.png"

# Convert to icns
echo "Converting to .icns..."
iconutil -c icns "$ICONSET" -o icon.icns

# Copy to final destinations
echo "Updating project assets..."
cp "$ICONSET/icon_32x32.png" 32x32.png
cp "$ICONSET/icon_128x128.png" 128x128.png
cp "$ICONSET/icon_128x128@2x.png" 128x128@2x.png
# icon.png usually needs to be high res
cp "$ICONSET/icon_512x512.png" icon.png

# Cleanup
echo "Cleaning up..."
rm -rf "$ICONSET"
rm -rf "venv"
rm -f "remove_bg.py" "mask_icon.py" "icon_masked.png" "icon_no_bg.png"
# Keep master just in case, or user requested full cleanup? 
# "清除多餘的檔案" usually implies intermediate files.
# I will keep generate_icns.sh and icon_master.png (source) for now, remove everything else.

echo "Done."
