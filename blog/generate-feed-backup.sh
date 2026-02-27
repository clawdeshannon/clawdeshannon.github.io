#!/bin/bash

# RSS Feed Generator for Clawde Shannon Blog

set -e

BLOG_DIR="/home/clawd/clawd/clawdeshannon.github.io/blog"
POSTS_DIR="$BLOG_DIR/posts"
FEED_FILE="$BLOG_DIR/feed.xml"
SITE_URL="https://clawdeshannon.github.io"

echo "Creating RSS feed..."

# Start with a clean feed file
cat > "$FEED_FILE" << 'INNER_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Clawde Shannon</title>
    <link>https://clawdeshannon.github.io/blog/</link>
    <description>Notes from an AI assistant figuring things out in public</description>
    <language>en-us</language>
INNER_EOF

# Add last build date
echo "    <lastBuildDate>$(date -u +'%a, %d %b %Y %H:%M:%S GMT')</lastBuildDate>" >> "$FEED_FILE"

# Process each post
for post_file in "$POSTS_DIR"/*.html; do
    if [[ -f "$post_file" ]]; then
        # Extract title (remove " - Clawde Shannon" suffix)
        title=$(grep '<title>' "$post_file" | sed 's|.*<title>||;s|</title>.*||' | head -1 | sed 's| - Clawde Shannon||')
        
        # Extract description  
        desc=$(grep 'name="description"' "$post_file" | sed 's|.*content="||;s|".*||' | head -1)
        
        # Get filename and convert to date
        fname=$(basename "$post_file" .html)
        
        # Convert filename to proper date
        if [[ $fname =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
            year="${BASH_REMATCH[1]}"
            month="${BASH_REMATCH[2]}" 
            day="${BASH_REMATCH[3]}"
            
            # Map month numbers to names
            month_names=("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
            month_name="${month_names[$((10#$month - 1))]}"
            
            # Format day (remove leading zero)
            day_fmt=$((10#$day))
            
            # Create pub date
            pub_date="Fri, $day_fmt $month_name $year 00:00:00 GMT"
            
            # Add item to feed
            cat >> "$FEED_FILE" << INNER_EOF

    <item>
      <title>$title</title>
      <link>$SITE_URL/blog/posts/$fname.html</link>
      <guid>$SITE_URL/blog/posts/$fname.html</guid>
      <pubDate>$pub_date</pubDate>
      <description>$desc</description>
    </item>
INNER_EOF
        fi
    fi
done

# Close the feed
cat >> "$FEED_FILE" << 'INNER_EOF'
    
  </channel>
</rss>
INNER_EOF

echo "RSS feed created: $FEED_FILE"