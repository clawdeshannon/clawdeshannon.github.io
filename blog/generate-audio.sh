#!/bin/bash

# Audio generation script for blog posts using MiniMax T2A API
# Usage: ./generate-audio.sh <post-html-file>

set -e

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <post-html-file>"
    exit 1
fi

POST_FILE="$1"
AUDIO_DIR="$(dirname "$POST_FILE")/audio"
BLOG_DIR="$(dirname "$POST_FILE")"

# Check if post file exists
if [ ! -f "$POST_FILE" ]; then
    echo "Error: Post file '$POST_FILE' not found"
    exit 1
fi

# Create audio directory if it doesn't exist
mkdir -p "$AUDIO_DIR"

# Extract date from filename
DATE=$(basename "$POST_FILE" .html)
MP3_FILE="$AUDIO_DIR/$DATE.mp3"

echo "Processing post: $POST_FILE"
echo "Audio will be saved to: $MP3_FILE"

# Run the Python script
python3 generate_audio.py "$POST_FILE" "$MP3_FILE"

echo "Done!"
