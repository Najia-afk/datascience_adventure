#!/bin/bash

# Script to generate a list of Python scripts from a source directory
# Usage: generate_script_list.sh <src_dir> <repo_name> <tmp_dir>

generate_script_list() {
    local src_dir=$1
    local repo_name=$2
    local tmp_dir=$3
    
    if [ ! -d "$src_dir" ]; then
        echo '<ul id="sidebar-list"><li>No scripts available</li></ul>'
        return
    fi
    
    # Create a temporary script list file
    local script_list_file="$tmp_dir/script_list.html"
    echo '<ul id="sidebar-list">' > "$script_list_file"
    
    # Get all subdirectories in the src directory
    local subdirs=$(find "$src_dir" -type d | sort)
    
    # Process each subdirectory
    for subdir in $subdirs; do
        # Skip the src directory itself
        if [ "$subdir" = "$src_dir" ]; then
            continue
        fi
        
        # Get the relative path from src
        local rel_path=${subdir#"$src_dir/"}
        # Only add subdir heading if files exist in this directory
        local has_py_files=$(find "$subdir" -maxdepth 1 -name "*.py" ! -name "__init__.py" | wc -l)
        
        if [ "$has_py_files" -gt 0 ]; then
            # Add subdirectory heading
            echo "<li class='subdir-heading'><strong>$(basename "$subdir")/</strong>" >> "$script_list_file"
            echo "<ul>" >> "$script_list_file"
            
            # Find Python files in this subdirectory, excluding __init__.py
            find "$subdir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | sort | while read script_path; do
                local script_name=$(basename "$script_path")
                # FIXED: Create path without src directory in the URL and ensure no trailing slash
                local subdirectory=$(basename "$subdir")
                local script_url="${repo_name}_src/${subdirectory}/${script_name}"
                # Clean up the URL path and ensure no trailing slash
                script_url=$(echo "$script_url" | sed 's|//*|/|g' | sed 's|/$||')
                echo "<li><a href=\"/$script_url\" target=\"_blank\">$script_name</a></li>" >> "$script_list_file"
            done
            
            echo "</ul></li>" >> "$script_list_file"
        fi
    done
    
    # Also add Python files directly in the src directory
    local root_has_py_files=$(find "$src_dir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | wc -l)
    
    if [ "$root_has_py_files" -gt 0 ]; then
        echo "<li class='subdir-heading'><strong>root/</strong>" >> "$script_list_file"
        echo "<ul>" >> "$script_list_file"
        
        # Also for root directory files
        find "$src_dir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | sort | while read script_path; do
            local script_name=$(basename "$script_path")
            # FIXED: Create correct URL path for root directory files with no trailing slash
            local script_url="${repo_name}_src/${script_name}"
            # Clean up the URL path and ensure no trailing slash
            script_url=$(echo "$script_url" | sed 's|//*|/|g' | sed 's|/$||')
            echo "<li><a href=\"/$script_url\" target=\"_blank\">$script_name</a></li>" >> "$script_list_file"
        done
        
        echo "</ul></li>" >> "$script_list_file"
    fi
    
    echo '</ul>' >> "$script_list_file"
    cat "$script_list_file"
}

# If script is called directly, execute the function with passed arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: generate_script_list.sh <src_dir> <repo_name> <tmp_dir>"
        exit 1
    fi
    
    generate_script_list "$1" "$2" "$3"
fi
