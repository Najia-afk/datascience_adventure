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
        echo "✅ Installed Pygments for Python syntax highlighting"
    fi
    
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
        
        # Read Python file
        py_content=$(cat "$py_file")
        
        # Generate HTML with Pygments using Python - with error handling
        html_content=$(sudo -u www-data /srv/htmx_website/venv/bin/python3 -c "
import pygments
import os
import sys
from pygments import highlight
from pygments.lexers import PythonLexer
from pygments.formatters import HtmlFormatter

code = '''$py_content'''

# Try to parse the Python code first to check for syntax errors
try:
    compile(code, '<string>', 'exec')
    is_valid = True
except SyntaxError as e:
    is_valid = False
    error_line = e.lineno
    error_msg = str(e)

if is_valid:
    # Code is valid, proceed with highlighting
    formatter = HtmlFormatter(style='default', linenos=True, full=True)
    html = highlight(code, PythonLexer(), formatter)
    css = formatter.get_style_defs('.highlight')
else:
    # Code has syntax errors, create a simpler display with error highlighted
    lines = code.split('\\n')
    html_lines = []
    
    for i, line in enumerate(lines, 1):
        if i == error_line:
            # Highlight the error line
            html_lines.append(f'<div class=\"error-line\">{i}: {line}</div>')
        else:
            html_lines.append(f'<div class=\"code-line\">{i}: {line}</div>')
    
    html = f'<div class=\"syntax-error\">SYNTAX ERROR: {error_msg}</div><pre>{\"\".join(html_lines)}</pre>'
    css = '.error-line { background-color: #ffcccc; color: #990000; } .syntax-error { color: red; font-weight: bold; margin-bottom: 10px; }'

print(f'''<!DOCTYPE html>
<html>
<head>
    <title>{os.path.basename('$py_file')}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 0; padding: 20px; }}
        .back-link {{ margin-bottom: 20px; }}
        .back-link a {{ text-decoration: none; color: #0066cc; }}
        .code-container {{ border: 1px solid #ddd; border-radius: 5px; overflow: auto; padding: 10px; }}
        .code-line {{ font-family: monospace; white-space: pre; }}
        {css}
    </style>
</head>
<body>
    <h2>{os.path.basename('$py_file')}</h2>
    <div class='code-container'>
        {html}
    </div>
</body>
</html>''')
" 2>/dev/null) || {
            # If Python script fails, create a simple error HTML file
            echo "⚠️ Error processing $py_file - syntax error detected"
            error_html="<!DOCTYPE html>
<html>
<head>
    <title>$(basename "$py_file") - Syntax Error</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .error { color: red; font-weight: bold; }
        .back-link { margin-bottom: 20px; }
        .back-link a { text-decoration: none; color: #0066cc; }
        pre { background-color: #f5f5f5; padding: 10px; border: 1px solid #ddd; border-radius: 5px; overflow: auto; }
    </style>
</head>
<body>
    <h2>$(basename "$py_file")</h2>
    <div class='error'>This file contains syntax errors and cannot be properly displayed.</div>
    <p>Please check the original source code for errors.</p>
    <pre>$(cat "$py_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')</pre>
</body>
</html>"
            echo "$error_html" | sudo tee "$html_file" > /dev/null
        }
        
        # Write HTML to file
        echo "$html_content" | sudo tee "$html_file" > /dev/null
        
        # Set proper permissions
        sudo chown www-data:www-data "$html_file"
        sudo chmod 644 "$html_file"
    done
    
    echo "✅ Converted Python files to HTML"
}

# If script is called directly, execute the function with passed arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: convert_python_to_html.sh <src_dir> <dest_dir> <repo_name>"
        exit 1
    fi
    
    convert_py_to_html "$1" "$2" "$3"
fi
