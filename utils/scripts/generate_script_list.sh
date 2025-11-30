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
    echo '<ul id="sidebar-list" class="sidebar-list">' > "$script_list_file"
    
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
            echo "<li class='repo-category'>" >> "$script_list_file"
            echo "<div class='category-header'><span class='name'>$(basename "$subdir")</span><span class='arrow'>▶</span></div>" >> "$script_list_file"
            echo "<ul class='category-scripts'>" >> "$script_list_file"
            
            # Find Python files in this subdirectory, excluding __init__.py
            find "$subdir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | sort | while read script_path; do
                local script_name=$(basename "$script_path")
                local script_base_name="${script_name%.py}"
                # FIXED: Create path without src directory in the URL and ensure no trailing slash
                local subdirectory=$(basename "$subdir")
                local script_url="${repo_name}_src/${subdirectory}/${script_base_name}.html"
                # Clean up the URL path and ensure no trailing slash
                script_url=$(echo "$script_url" | sed 's|//*|/|g' | sed 's|/$||')
                echo "<li><a href=\"/$script_url\" hx-boost=\"false\" onclick=\"window.open(this.href, 'CodeViewer', 'width=1200,height=800'); return false;\">$script_name</a></li>" >> "$script_list_file"
            done
            
            echo "</ul></li>" >> "$script_list_file"
        fi
    done
    
    # Also add Python files directly in the src directory
    local root_has_py_files=$(find "$src_dir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | wc -l)
    
    if [ "$root_has_py_files" -gt 0 ]; then
        echo "<li class='repo-category'>" >> "$script_list_file"
        echo "<div class='category-header'><span class='name'>Main Scripts</span><span class='arrow'>▶</span></div>" >> "$script_list_file"
        echo "<ul class='category-scripts'>" >> "$script_list_file"
        
        # Also for root directory files
        find "$src_dir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | sort | while read script_path; do
            local script_name=$(basename "$script_path")
            local script_base_name="${script_name%.py}"
            # FIXED: Create correct URL path for root directory files with no trailing slash
            local script_url="${repo_name}_src/${script_base_name}.html"
            # Clean up the URL path and ensure no trailing slash
            script_url=$(echo "$script_url" | sed 's|//*|/|g' | sed 's|/$||')
            echo "<li><a href=\"/$script_url\" hx-boost=\"false\" onclick=\"window.open(this.href, 'CodeViewer', 'width=1200,height=800'); return false;\">$script_name</a></li>" >> "$script_list_file"
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
