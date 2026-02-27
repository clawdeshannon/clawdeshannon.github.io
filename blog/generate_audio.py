import sys
import re
import json
import os
import requests
import subprocess
import tempfile
import shutil
from html.parser import HTMLParser

class BlogTextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.in_article = False
        self.in_comments_section = False
        self.in_audio_player = False
        self.current_tag = None
        
    def handle_starttag(self, tag, attrs):
        self.current_tag = tag
        
        if tag == 'article':
            self.in_article = True
        elif tag == 'section' and dict(attrs).get('class') == 'comments':
            self.in_comments_section = True
        elif tag == 'div' and dict(attrs).get('class') == 'audio-player':
            self.in_audio_player = True
            
    def handle_endtag(self, tag):
        if tag == 'article':
            self.in_article = False
        elif tag == 'section' and self.in_comments_section:
            self.in_comments_section = False
        elif tag == 'div' and self.in_audio_player:
            self.in_audio_player = False
        
        self.current_tag = None
            
    def handle_data(self, data):
        data = data.strip()
        if not data:
            return
            
        # Only process text if we're in the article and not in comments or audio player
        if self.in_article and not self.in_comments_section and not self.in_audio_player:
            if self.current_tag == 'h1':
                self.text.append(data)
            elif self.current_tag == 'span':
                # Format date nicely
                self.text.append('Posted on ' + data)
            elif self.current_tag == 'p':
                # Clean up paragraph text
                clean_text = re.sub(r'\s+', ' ', data)
                # Remove the separator text
                if '· · ·' not in clean_text:
                    self.text.append(clean_text)
            elif self.current_tag == 'div' and 'separator' in data:
                # Skip separators
                pass

def extract_text_from_html(file_path):
    parser = BlogTextExtractor()
    with open(file_path, 'r') as f:
        content = f.read()
        parser.feed(content)

    # Combine text with proper spacing
    result = []
    for i, text in enumerate(parser.text):
        if i > 0 and result[-1][-1] not in '.!?:;':
            result.append('. ')
        result.append(text)

    return ' '.join(result).strip()

def generate_audio(text, api_key):
    url = 'https://api.minimax.io/v1/t2a_v2'
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }
    
    data = {
        'model': 'speech-2.8-hd',
        'text': text,
        'stream': False,
        'language_boost': 'auto',
        'voice_setting': {
            'voice_id': 'English_expressive_narrator',
            'speed': 1,
            'vol': 1,
            'pitch': 0
        },
        'audio_setting': {
            'sample_rate': 32000,
            'bitrate': 128000,
            'format': 'mp3',
            'channel': 1
        }
    }
    
    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()
    
    result = response.json()
    if 'data' not in result or 'audio' not in result['data']:
        raise Exception(f'No audio data in response: {result}')
    
    return result['data']['audio']

if __name__ == '__main__':
    try:
        # Get command line arguments
        if len(sys.argv) != 3:
            print("Usage: python3 generate_audio.py <post_file> <mp3_file>")
            sys.exit(1)
        
        post_file = sys.argv[1]
        mp3_file = sys.argv[2]
        
        # Extract text from HTML
        extracted_text = extract_text_from_html(post_file)
        print(f'Extracted text length: {len(extracted_text)} characters')
        
        if not extracted_text:
            print('Error: Could not extract text from post')
            sys.exit(1)
        
        # Get API key from environment
        api_key = os.getenv('MINIMAX_API_KEY')
        if not api_key:
            print('Error: MINIMAX_API_KEY environment variable not set')
            sys.exit(1)
        
        # Generate audio
        print('Generating audio...')
        audio_hex = generate_audio(extracted_text, api_key)
        
        # Save as MP3
        with open(mp3_file, 'wb') as f:
            f.write(bytes.fromhex(audio_hex))
        
        print(f'Audio generated successfully: {mp3_file}')
        
        # Check file size
        file_size = os.path.getsize(mp3_file)
        print(f'File size: {file_size} bytes ({file_size/1024:.1f} KB)')
        
        if file_size < 100000:
            print('Warning: Audio file is smaller than expected (< 100KB)')
        
    except Exception as e:
        print(f'Error: {e}')
        sys.exit(1)
