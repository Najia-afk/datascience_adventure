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
        try:
            return render_template('index.html')
        except Exception as e:
            app.logger.error(f"Error rendering index: {str(e)}")
            abort(500)

    @app.route('/header/')
    def header():
        try:
            return render_template('templates/header.html')
        except Exception as e:
            app.logger.error(f"Error rendering header: {str(e)}")
            abort(404)

    @app.route('/footer/')
    def footer():
        try:
            return render_template('templates/footer.html')
        except Exception as e:
            app.logger.error(f"Error rendering footer: {str(e)}")
            abort(404)

    @app.route('/summary/')
    def summary():
        try:
            return render_template('templates/summary.html')
        except Exception as e:
            app.logger.error(f"Error rendering summary: {str(e)}")
            abort(404)

    @app.route('/load-home/')
    def load_home():
        try:
            return render_template('templates/home.html')
        except Exception as e:
            app.logger.error(f"Error rendering home: {str(e)}")
            abort(404)
    
    # Dynamic route for mission pages
    @app.route('/<path:mission_path>/')
    def mission_page(mission_path):
        try:
            return render_template(f'{mission_path}.html')
        except Exception as e:
            app.logger.error(f"Error rendering {mission_path}: {str(e)}")
            abort(404)

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
    
    # Error handler for 500
    @app.errorhandler(500)
    def server_error(e):
        app.logger.error(f"Server error: {str(e)}")
        return "Internal server error. Please check server logs.", 500

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)

