from flask import Flask, render_template, send_from_directory, abort
import os
import re

# Function to create the Flask app
def create_app():
    # Define the base directory relative to this file
    base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static')

    # Determine where the content (processed missions, converted python files) is located
    # In Docker, this is /var/www/htmx_website
    # Locally, we default to the static folder (though content might not be there if not generated)
    if os.path.exists('/var/www/htmx_website'):
        content_dir = '/var/www/htmx_website'
    else:
        content_dir = base_dir

    # Use the root as template_folder
    app = Flask(__name__, static_folder=content_dir, template_folder=content_dir)
    app.config['CONTENT_DIR'] = content_dir

    # Route for serving converted script HTML files
    @app.route('/<path:repo>_src/<path:filename>')
    def serve_script_html(repo, filename):
        src_dir = os.path.join(app.config['CONTENT_DIR'], f"{repo}_src")
        return send_from_directory(src_dir, filename)
    
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

    @app.route('/contact/')
    def contact():
        return render_template('templates/contact.html')
    
    # Dynamic route for mission pages
    @app.route('/<path:mission_path>/')
    def mission_page(mission_path):
        return render_template(f'{mission_path}.html')

    # Dynamic route for mission content HTML files
    @app.route('/<path:mission_path>_content.html')
    def mission_content(mission_path):
        content_file = f'{mission_path}_content.html'
        # Use the configured content directory
        content_dir = app.config['CONTENT_DIR']
        file_path = os.path.join(content_dir, content_file)
        if os.path.exists(file_path):
            return send_from_directory(content_dir, content_file)
        abort(404)

    # Generic route for static files - properly fixed version
    @app.route('/<path:filename>.py/')
    def serve_static(filename):
        # Clean up the filename - ensure trailing slashes are removed
        filename = re.sub(r'/+', '/', filename).rstrip('/')
        
    
        base_name, ext = os.path.splitext(filename)
        html_filename = base_name + '.html'
        content_dir = app.config['CONTENT_DIR']
        html_path = os.path.join(content_dir, html_filename)
        
        if os.path.exists(html_path):
            return send_from_directory(content_dir, html_filename)
        
        # If not found, return 404
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

