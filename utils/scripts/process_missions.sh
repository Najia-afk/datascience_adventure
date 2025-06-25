#!/bin/bash

# Script to process mission HTML files with layout templates
# Usage: process_missions.sh <html_file> <tmp_dir> <layout_file> <summary_file> <workdir> <www_dir>

set -e

process_mission_with_layout() {
    local html_file=$1
    local tmp_dir=$2
    local layout_file=$3
    local summary_file=$4
    local workdir=$5
    local www_dir=$6
    
    local mission_name=$(basename "$html_file" .html)
    echo "Processing $mission_name HTML with layout template..."
    
    # Extract mission number
    local mission_number=${mission_name#mission}
    echo "Detected mission number: $mission_number"
    
    # Copy the mission HTML to temp dir
    cp "$html_file" "$tmp_dir/mission_content.html"
    
    # Look for mission info in the summary.html template
    if [ -f "$summary_file" ]; then
        echo "Looking for mission $mission_number info in summary.html..."
        
        # Extract the mission title
        local mission_title=$(grep -A 1 "Mission $mission_number:" "$summary_file" | grep "<h2>" | sed 's/<h2>\(.*\)<\/h2>/\1/' | tr -d '\n')
        
        # Extract the mission description (third paragraph in the grid-item, not fourth)
        local mission_desc=$(grep -A 10 "Mission $mission_number:" "$summary_file" | grep -m 3 "<p>" | tail -n 1 | sed 's/<p>\(.*\)<\/p>/\1/' | tr -d '\n')
        
        echo "Extracted title: $mission_title"
        echo "Extracted description: $mission_desc"
        
        # If we found both title and description, use them
        if [ -n "$mission_title" ] && [ -n "$mission_desc" ]; then
            echo "Will use extracted mission info for $mission_name"
        else
            echo "Could not extract complete mission info, using defaults"
            mission_title="Mission $mission_number: Data Science Project"
            mission_desc="Exploring data science concepts and techniques."
        fi
    else
        echo "Summary file not found at $summary_file, using default mission info"
        mission_title="Mission $mission_number: Data Science Project"
        mission_desc="Exploring data science concepts and techniques."
    fi
    
    # Look for scripts in the src directory for this mission
    local script_list=""
    local repo_name=$(basename $(dirname "$html_file"))
    local src_dir="$workdir/$repo_name/src"
    
    # Generate script list from src directory
    source $(dirname "$0")/generate_script_list.sh
    script_list=$(generate_script_list "$src_dir" "$repo_name" "$tmp_dir")
    
    # Create a modified layout with the correct mission name and script list
    local modified_layout="$tmp_dir/modified_layout.html"
    cp "$layout_file" "$modified_layout"
    
    # Update title and description with extracted info
    sed -i "s|<h1>Mission: Data Science Project</h1>|<h1>$mission_title</h1>|g" "$modified_layout"
    sed -i "s|<p>Exploring data science concepts and techniques.</p>|<p>$mission_desc</p>|g" "$modified_layout"
    
    # Update mission number in title tag
    sed -i "s/Mission: Data/Mission $mission_number: Data/g" "$modified_layout"
    # Update mission number in h1 tag
    sed -i "s/<h1>Mission: /<h1>Mission $mission_number: /g" "$modified_layout"
    
    # Create a script list placeholder file to avoid sed escaping issues
    echo "$script_list" > "$tmp_dir/script_list_content.html"
    
    # Use awk to replace the sidebar list - more reliable than sed for complex HTML
    awk '{
        if ($0 ~ /<ul id="sidebar-list">/) {
            system("cat '"$tmp_dir/script_list_content.html"'");
            in_list = 1;
        } else if (in_list && $0 ~ /<\/ul>/) {
            in_list = 0;
        } else if (!in_list) {
            print $0;
        }
    }' "$modified_layout" > "$tmp_dir/layout_with_scripts.html"
    
    # Move the modified file back
    mv "$tmp_dir/layout_with_scripts.html" "$modified_layout"
    
    # Update GitHub repo link and Colab button URL
    source $(dirname "$0")/update_layout.sh
    update_layout "$modified_layout" "$repo_name"
    
    # Add resize listener script to the merged file if not already present
    if ! grep -q "sendHeight" "$modified_layout"; then
        cat <<EOF >> "$modified_layout"
<script>
    function sendHeight() {
        var documentHeight = document.body.scrollHeight;
        console.log("Iframe content height:", documentHeight);
        window.parent.postMessage({ height: documentHeight }, "*");
    }
    window.addEventListener("load", function() {
        sendHeight();
    });
    window.addEventListener("resize", function() {
        sendHeight();
    });
</script>
</body>
EOF
        # Remove the original closing body tag to avoid duplicates
        sed -i 's|</body>||g' "$modified_layout"
        # Add back the closing HTML tag if needed
        echo "</html>" >> "$modified_layout"
        echo "Added resize listener script to merged file"
    fi
    
    # Copy the modified layout and content to the web directory
    sudo cp "$modified_layout" "$www_dir/${mission_name}.html"
    sudo cp "$html_file" "$www_dir/${mission_name}_content.html"
    
    # Set proper permissions for both files
    sudo chown www-data:www-data "$www_dir/${mission_name}.html"
    sudo chown www-data:www-data "$www_dir/${mission_name}_content.html"
    sudo chmod 644 "$www_dir/${mission_name}.html"
    sudo chmod 644 "$www_dir/${mission_name}_content.html"
    
    echo "✅ Created merged ${mission_name}.html with layout in $www_dir/"
    return 0
}

# Execute the function with passed arguments
if [ "$#" -lt 6 ]; then
    echo "Usage: process_missions.sh <html_file> <tmp_dir> <layout_file> <summary_file> <workdir> <www_dir>"
    exit 1
fi

process_mission_with_layout "$1" "$2" "$3" "$4" "$5" "$6"
