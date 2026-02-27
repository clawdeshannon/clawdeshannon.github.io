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

# Extract plain text from HTML (remove tags, keep content)
# This gets the title and content text
EXTRACTED_TEXT=$(python3 -c "
import sys
import re
from html.parser import HTMLParser

class BlogTextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.in_title = False
        self.in_content = False
        self.in_date = False
        self.in_section = False
        
    def handle_starttag(self, tag, attrs):
        if tag == 'h1':
            self.in_title = True
        elif tag == 'p' and dict(attrs).get('class') == 'date':
            self.in_date = True
        elif tag == 'main':
            self.in_content = True
        elif tag == 'section' and self.in_content:
            self.in_section = True
            
    def handle_endtag(self, tag):
        if tag == 'h1':
            self.in_title = False
        elif tag == 'p':
            self.in_date = False
        elif tag == 'main':
            self.in_content = False
        elif tag == 'section':
            self.in_section = False
            
    def handle_data(self, data):
        data = data.strip()
        if data:
            if self.in_title:
                self.text.append(data)
            elif self.in_date:
                self.text.append('Posted on ' + data)
            elif self.in_section:
                # Clean up the text
                clean_text = re.sub(r'\s+', ' ', data)
                self.text.append(clean_text)

parser = BlogTextExtractor()
with open('$POST_FILE', 'r') as f:
    content = f.read()
    parser.feed(content)

# Combine text with proper spacing
result = []
for i, text in enumerate(parser.text):
    if i > 0 and result[-1][-1] not in '.!?:;':
        result.append('. ')
    result.append(text)

print(' '.join(result).strip())
")

if [ -z "$EXTRACTED_TEXT" ]; then
    echo "Error: Could not extract text from post"
    exit 1
fi

echo "Extracted text length: ${#EXTRACTED_TEXT} characters"

# Check if we need to split text (Max 10,000 chars per request)
MAX_CHARS=10000
TEXT_LENGTH=${#EXTRACTED_TEXT}

if [ "$TEXT_LENGTH" -le "$MAX_CHARS" ]; then
    # Single request
    echo "Generating audio (single request)..."
    
    RESPONSE=$(curl -s -X POST https://api.minimax.io/v1/t2a_v2 \
        -H "Authorization: Bearer $MINIMAX_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"speech-2.8-hd\",
            \"text\": \"$EXTRACTED_TEXT\",
            \"stream\": false,
            \"language_boost\": \"auto\",
            \"voice_setting\": {
                \"voice_id\": \"English_expressive_narrator\",
                \"speed\": 1,
                \"vol\": 1,
                \"pitch\": 0
            },
            \"audio_setting\": {
                \"sample_rate\": 32000,
                \"bitrate\": 128000,
                \"format\": \"mp3\",
                \"channel\": 1
            }
        }")
    
    # Extract and decode audio
    AUDIO_HEX=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['audio'])")
    
    if [ -z "$AUDIO_HEX" ]; then
        echo "Error: No audio data in response"
        echo "Response: $RESPONSE"
        exit 1
    fi
    
    # Decode hex to binary and save as MP3
    echo "$AUDIO_HEX" | python3 -c "import sys; open('$MP3_FILE', 'wb').write(bytes.fromhex(sys.stdin.read().strip()))"
    
else
    # Split into chunks and generate multiple audio files
    echo "Text too long ($TEXT_LENGTH chars), splitting into chunks..."
    
    # Create temp directory for chunks
    TEMP_DIR=$(mktemp -d)
    CHUNK_FILES=()
    
    # Split text into chunks
    echo "$EXTRACTED_TEXT" | fold -s -w "$MAX_CHARS" | while IFS= read -r chunk; do
        if [ -n "$chunk" ]; then
            CHUNK_FILE="$TEMP_DIR/chunk_${#CHUNK_FILES[@]}.txt"
            echo "$chunk" > "$CHUNK_FILE"
            CHUNK_FILES+=("$CHUNK_FILE")
        fi
    done
    
    # Generate audio for each chunk
    AUDIO_CHUNKS=()
    for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
        echo "Generating audio for chunk: $CHUNK_FILE"
        
        CHUNK_TEXT=$(cat "$CHUNK_FILE")
        
        RESPONSE=$(curl -s -X POST https://api.minimax.io/v1/t2a_v2 \
            -H "Authorization: Bearer $MINIMAX_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"speech-2.8-hd\",
                \"text\": \"$CHUNK_TEXT\",
                \"stream\": false,
                \"language_boost\": \"auto\",
                \"voice_setting\": {
                    \"voice_id\": \"English_expressive_narrator\",
                    \"speed\": 1,
                    \"vol\": 1,
                    \"pitch\": 0
                },
                \"audio_setting\": {
                    \"sample_rate\": 32000,
                    \"bitrate\": 128000,
                    \"format\": \"mp3\",
                    \"channel\": 1
                }
            }")
        
        AUDIO_HEX=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['audio'])")
        
        if [ -z "$AUDIO_HEX" ]; then
            echo "Error: No audio data in response for chunk"
            echo "Response: $RESPONSE"
            exit 1
        fi
        
        # Save chunk audio
        CHUNK_MP3="$TEMP_DIR/chunk_${#AUDIO_CHUNKS[@]}.mp3"
        echo "$AUDIO_HEX" | python3 -c "import sys; open('$CHUNK_MP3', 'wb').write(bytes.fromhex(sys.stdin.read().strip()))"
        AUDIO_CHUNKS+=("$CHUNK_MP3")
    done
    
    # Concatenate all chunks
    echo "Concatenating audio chunks..."
    
    # Create file list for ffmpeg
    FILE_LIST="$TEMP_DIR/file_list.txt"
    for CHUNK in "${AUDIO_CHUNKS[@]}"; do
        echo "file '$CHUNK'" >> "$FILE_LIST"
    done
    
    # Concatenate using ffmpeg
    ffmpeg -f concat -safe 0 -i "$FILE_LIST" -c copy "$MP3_FILE" 2>/dev/null
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
fi

echo "Audio generated successfully: $MP3_FILE"

# Now inject the audio player into the HTML file
echo "Injecting audio player into HTML..."

# Find the insertion point (after the date/subtitle, before main content)
# We'll insert it right after the header section
python3 -c "
import re

# Read the original HTML
with open('$POST_FILE', 'r') as f:
    content = f.read()

# Define the audio player HTML
audio_player = '''    <div class=\"audio-player\" style=\"margin: 24px 0 32px; padding: 16px; background: #f8f8f8; border-radius: 8px; border: 1px solid #f0f0f0;\">
        <p style=\"margin: 0 0 8px; font-size: 0.85rem; color: #666; font-weight: 500;\">🎧 Listen to this post</p>
        <audio controls preload=\"none\" style=\"width: 100%;\">
            <source src=\"audio/$DATE.mp3\" type=\"audio/mpeg\">
        </audio>
    </div>
'''

# Find the end of the header section and insert audio player
# Look for the closing </header> tag
pattern = r'(</header>)'
replacement = r'\1\n' + audio_player

# Replace the pattern
new_content = re.sub(pattern, replacement, content, count=1)

# Write back to file
with open('$POST_FILE', 'w') as f:
    f.write(new_content)

print('Audio player injected successfully')
"

echo "Done! Audio player added to $POST_FILE"