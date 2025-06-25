#!/bin/bash

# Script to update the layout template with correct URLs and links
# Usage: update_layout.sh <layout_file> <repo_name>

update_layout() {
    local modified_layout=$1
    local repo_name=$2
    
    # Convert repo name to lowercase for GitHub URLs
    local github_repo=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]')
    
    echo "Updating layout template for repository: $github_repo"
    
    # Update GitHub repo link
    sed -i "s|github.com/Najia-afk/mission|github.com/Najia-afk/$github_repo|g" "$modified_layout"
    
    # Update iframe src to point to the correct content file
    mission_name=$(basename "$github_repo")
    sed -i "s|id=\"main-iframe\" src=\"\"|id=\"main-iframe\" src=\"/${mission_name}_content.html\"|g" "$modified_layout"

    # Update the Colab button URL
    local colab_url="https://colab.research.google.com/github/Najia-afk/$github_repo/blob/main/$github_repo.ipynb"
    echo "Setting Colab button URL to $colab_url"

    # First try matching the JS pattern
    if grep -q "colabButton.href" "$modified_layout"; then
        sed -i "s|colabButton.href = 'https://colab.research.google.com/github/Najia-afk/[^']*'|colabButton.href = 'https://colab.research.google.com/github/Najia-afk/$github_repo/blob/main/$github_repo.ipynb'|g" "$modified_layout"
    fi
    
    # Then try the HTML pattern for direct href attribute
    sed -i "s|id=\"colab-button\" class=\"button-colab\" href=\"[^\"]*\"|id=\"colab-button\" class=\"button-colab\" href=\"https://colab.research.google.com/github/Najia-afk/$github_repo/blob/main/$github_repo.ipynb\"|g" "$modified_layout"
    
    # If there's no href attribute yet, add it
    sed -i "s|id=\"colab-button\" class=\"button-colab\">|id=\"colab-button\" class=\"button-colab\" href=\"https://colab.research.google.com/github/Najia-afk/$github_repo/blob/main/$github_repo.ipynb\">|g" "$modified_layout"
}

# If script is called directly, execute the function with passed arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: update_layout.sh <layout_file> <repo_name>"
        exit 1
    fi
    
    update_layout "$1" "$2"
fi
