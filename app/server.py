from flask import Flask, render_template, send_from_directory, abort, Response
import os
import re
import pygments
from pygments import highlight
from pygments.lexers import PythonLexer
from pygments.formatters import HtmlFormatter

# Function to create the Flask app
def create_app():
    # Use the root as template_folder
    app = Flask(__name__, static_folder="/var/www/htmx_website/", template_folder="/var/www/htmx_website/")
    
    # Route for main website pages
    @app.route('/')
    def index():
        return render_template('index.html')

    @app.route('/header/')
    def header():
        return render_template('templates/header.html')

    @app.route('/footer/')
    def footer():
        return render_template('templates/footer.html')

    @app.route('/summary/')
    def summary():
        return render_template('templates/summary.html')

    @app.route('/load-home/')
    def load_home():
        return render_template('templates/home.html')
    
    # Dynamic route for mission pages
    @app.route('/<path:mission_path>/')
    def mission_page(mission_path):
        # Check if this is a mission route
        if re.match(r'^mission\d+$', mission_path):
            # Try to serve the mission HTML file
            try:
                return render_template(f'{mission_path}.html')
            except:
                abort(404)
        # Otherwise, try to handle other paths
        else:
            try:
                return render_template(mission_path)
            except:
                abort(404)
    
    # Dynamic route for mission content HTML files
    @app.route('/<path:mission_path>_content.html')
    def mission_content(mission_path):
        # Check if this is a mission content path
        if re.match(r'^mission\d+$', mission_path):
            content_file = f'{mission_path}_content.html'
            if os.path.exists(os.path.join('/var/www/htmx_website', content_file)):
                return send_from_directory('/var/www/htmx_website', content_file)
        abort(404)
    
    # Generic route for static files
    @app.route('/<path:filename>')
    def serve_static(filename):
        # Clean up the filename (remove multiple slashes)
        filename = re.sub(r'/+', '/', filename)
        # Remove any trailing slash
        filename = filename.rstrip('/')
        
        # Check if file exists in the static directory
        if os.path.exists(os.path.join('/var/www/htmx_website', filename)):
            # For Python files, convert to syntax highlighted HTML
            if filename.endswith('.py'):
                # Read the Python file
                with open(os.path.join('/var/www/htmx_website', filename), 'r') as f:
                    code = f.read()
                
                # Generate syntax highlighted HTML
                lexer = PythonLexer()
                formatter = HtmlFormatter(style='default', linenos=True, full=True)
                highlighted_code = highlight(code, lexer, formatter)
                
                # Get the CSS styles for the highlighting
                css = formatter.get_style_defs('.highlight')
                
                # Add the CSS and a back button to the highlighted code
                html = f"""
                <!DOCTYPE html>
                <html>
                <head>
                    <title>{os.path.basename(filename)}</title>
                    <style>
                        body {{ font-family: Arial, sans-serif; margin: 0; padding: 20px; }}
                        .back-link {{ margin-bottom: 20px; }}
                        .back-link a {{ text-decoration: none; color: #0066cc; }}
                        .code-container {{ border: 1px solid #ddd; border-radius: 5px; overflow: auto; }}
                        {css}
                    </style>
                </head>
                <body>
                    <div class="back-link">
                        <a href="javascript:history.back()">&lt; Back to mission</a>
                    </div>
                    <h2>{os.path.basename(filename)}</h2>
                    <div class="code-container">
                        {highlighted_code}
                    </div>
                </body>
                </html>
                """
                
                return Response(html, mimetype='text/html')
            
            return send_from_directory('/var/www/htmx_website', filename)
        
        # Try adding .html if the file without extension doesn't exist
        if not os.path.exists(os.path.join('/var/www/htmx_website', filename)) and not filename.endswith('.html'):
            if os.path.exists(os.path.join('/var/www/htmx_website', filename + '.html')):
                return send_from_directory('/var/www/htmx_website', filename + '.html')
        
        abort(404)

    # Error handler for 404
    @app.errorhandler(404)
    def not_found(e):
        return render_template('404.html'), 404

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)
