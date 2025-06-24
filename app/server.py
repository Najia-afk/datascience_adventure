from flask import Flask, render_template, send_from_directory, abort
import os
import re

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
        return render_template(f'{mission_path}.html')

    # Dynamic route for mission content HTML files
    @app.route('/<path:mission_path>_content.html')
    def mission_content(mission_path):
        content_file = f'{mission_path}_content.html'
        file_path = os.path.join('/var/www/htmx_website', content_file)
        if os.path.exists(file_path):
            return send_from_directory('/var/www/htmx_website', content_file)
        abort(404)

    # Generic route for static files - fixed version
    @app.route('/<path:filename>')
    def serve_static(filename):
        # Clean up the filename
        filename = re.sub(r'/+', '/', filename).rstrip('/')
        file_path = os.path.join('/var/www/htmx_website', filename)
        
        # Check if the file exists
        if os.path.exists(file_path):
            return send_from_directory('/var/www/htmx_website', filename)
        
        # Try with .html extension
        html_path = file_path + '.html'
        if os.path.exists(html_path):
            return send_from_directory('/var/www/htmx_website', filename + '.html')
        
        # File not found
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

