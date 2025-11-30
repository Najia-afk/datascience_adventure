#!/bin/bash

# Script to convert Python files to HTML with syntax highlighting
# Usage: convert_python_to_html.sh <src_dir> <dest_dir> <repo_name>

convert_py_to_html() {
    local src_dir=$1
    local dest_dir=$2
    local repo_name=$3
    
    echo "Converting Python files to HTML in $src_dir..."
    
    # Install pygments if not already installed
    if ! sudo -u www-data /srv/htmx_website/venv/bin/pip list | grep -q pygments; then
        sudo -u www-data /srv/htmx_website/venv/bin/pip install pygments
        echo " Installed Pygments for Python syntax highlighting"
    fi
    
    # Create a temporary python script for conversion
    cat << 'EOF' > /tmp/convert_syntax.py
import sys
import os
from pygments import highlight
from pygments.lexers import PythonLexer
from pygments.formatters import HtmlFormatter

if len(sys.argv) < 2:
    sys.exit(1)

file_path = sys.argv[1]
try:
    with open(file_path, 'r') as f:
        code = f.read()
except Exception as e:
    print(f"Error reading file: {e}", file=sys.stderr)
    sys.exit(1)

# Try to parse the Python code first to check for syntax errors
try:
    compile(code, '<string>', 'exec')
    is_valid = True
    error_msg = ""
    error_line = -1
except SyntaxError as e:
    is_valid = False
    error_line = e.lineno
    error_msg = str(e)

if is_valid:
    # Code is valid, proceed with highlighting
    # Use 'monokai' style for dark theme compatibility
    # full=False ensures we only get the code block, not a full HTML document
    formatter = HtmlFormatter(style='monokai', linenos=True, full=False, cssclass='highlight')
    html = highlight(code, PythonLexer(), formatter)
    css = formatter.get_style_defs('.highlight')
else:
    # Code has syntax errors, create a simpler display with error highlighted
    lines = code.split('\n')
    html_lines = []
    
    for i, line in enumerate(lines, 1):
        if i == error_line:
            # Highlight the error line
            html_lines.append(f'<div class="error-line">{i}: {line}</div>')
        else:
            html_lines.append(f'<div class="code-line">{i}: {line}</div>')
    
    html = f'<div class="syntax-error">SYNTAX ERROR: {error_msg}</div><pre>{"".join(html_lines)}</pre>'
    css = '.error-line { background-color: #ffcccc; color: #990000; } .syntax-error { color: red; font-weight: bold; margin-bottom: 10px; }'

print(f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{os.path.basename(file_path)} - DataScience Adventure</title>
    <link rel="stylesheet" href="/styles/variables.css">
    <link rel="stylesheet" href="/styles/base.css">
    <link rel="stylesheet" href="/styles/interactive.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Fira+Code&display=swap" rel="stylesheet">
    <style>
        /* Pygments styles injected directly */
        {css}
        
        /* Ensure code background matches container */
        .highlight {{ background: transparent !important; }}
        .linenos {{ color: #666 !important; border-right: 1px solid #333 !important; margin-right: 10px !important; }}
    </style>
</head>
<body class="code-view-body">
    <div class="code-header">
        <h2>{os.path.basename(file_path)}</h2>
        <div class="back-link">
            <a href="javascript:window.close()">Close Window</a>
        </div>
    </div>
    
    <div class="code-container">
        {html}
    </div>
</body>
</html>''')
EOF

    # Find all Python files and convert them
    find "$src_dir" -type f -name "*.py" ! -name "__init__.py" | while read py_file; do
        # Get relative path
        rel_path=${py_file#"$src_dir/"}
        
        # Determine destination directory based on subdirectory name
        subdir=$(dirname "$rel_path")
        if [ "$subdir" = "." ]; then
            # Root directory files go to "root"
            target_dir="$dest_dir/root"
        else
            # Use the actual subdirectory name
            target_dir="$dest_dir/$subdir"
        fi
        
        # Create target directory if it doesn't exist
        sudo mkdir -p "$target_dir"
        
        # Get the basename without extension
        base_name=$(basename "$py_file" .py)
        html_file="$target_dir/${base_name}.html"
        
        echo "Converting $py_file to $html_file"
        
        # Generate HTML using the python script
        if ! sudo -u www-data /srv/htmx_website/venv/bin/python3 /tmp/convert_syntax.py "$py_file" > /tmp/temp_output.html 2>/dev/null; then
             echo " Error processing $py_file - syntax error detected"
             # Fallback error HTML
             cat <<HTML > /tmp/temp_output.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Syntax Error</title>
    <link rel="stylesheet" href="/styles/variables.css">
    <link rel="stylesheet" href="/styles/base.css">
    <link rel="stylesheet" href="/styles/interactive.css">
    <style>
        .error { color: #ff4444; font-weight: bold; margin-bottom: 1rem; }
        pre { background-color: rgba(0,0,0,0.3); padding: 1rem; border: 1px solid var(--border); border-radius: var(--radius-sm); overflow: auto; color: var(--text-main); }
    </style>
</head>
<body class="code-view-body">
    <div class="code-header">
        <h2>Syntax Error</h2>
        <div class="back-link">
            <a href="#" onclick="window.close()">Close Window</a>
        </div>
    </div>
    <div class='error'>This file contains syntax errors.</div>
    <pre>$(cat "$py_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')</pre>
</body>
</html>
HTML
        fi
        
        # Move output to final destination
        sudo mv /tmp/temp_output.html "$html_file"
        
        # Set proper permissions
        sudo chown www-data:www-data "$html_file"
        sudo chmod 644 "$html_file"
    done
    
    # Clean up
    rm -f /tmp/convert_syntax.py
    
    echo " Converted Python files to HTML"
}

# If script is called directly, execute the function with passed arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: convert_python_to_html.sh <src_dir> <dest_dir> <repo_name>"
        exit 1
    fi
    
    convert_py_to_html "$1" "$2" "$3"
fi
