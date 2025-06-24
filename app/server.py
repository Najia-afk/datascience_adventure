from flask import Flask, render_template, send_from_directory
import os

# Function to create the Flask app
def create_app():
    # Use the root as template_folder
    app = Flask(__name__, static_folder="/var/www/htmx_website/", template_folder="/var/www/htmx_website/")
    
    # Debug function to check template paths
    def debug_template_path(template_name):
        template_paths = [
            os.path.join("/var/www/htmx_website/", template_name),
            os.path.join("/var/www/htmx_website/templates/", template_name)
        ]
        for path in template_paths:
            if os.path.exists(path):
                print(f"Template exists at: {path}")
            else:
                print(f"Template NOT found at: {path}")
    
    # Route for main website pages
    @app.route('/')
    def index():
        try:
            return render_template('index.html')
        except Exception as e:
            print(f"Error rendering index.html: {str(e)}")
            debug_template_path('index.html')
            return "Error loading index page. Please check server logs."

    @app.route('/header/')
    def header():
        debug_template_path('header.html')
        try:
            # Try without 'templates/' prefix first
            return render_template('header.html')
        except Exception as e1:
            print(f"Error with direct path: {str(e1)}")
            try:
                # Fallback to with 'templates/' prefix
                return render_template('templates/header.html')
            except Exception as e2:
                print(f"Error with templates/ prefix: {str(e2)}")
                return "Header template not found."

    @app.route('/footer/')
    def footer():
        debug_template_path('footer.html')
        try:
            # Try without 'templates/' prefix first
            return render_template('footer.html')
        except Exception as e1:
            print(f"Error with direct path: {str(e1)}")
            try:
                # Fallback to with 'templates/' prefix
                return render_template('templates/footer.html')
            except Exception as e2:
                print(f"Error with templates/ prefix: {str(e2)}")
                return "Footer template not found."

    @app.route('/summary/')
    def summary():
        debug_template_path('summary.html')
        try:
            # Try without 'templates/' prefix first
            return render_template('summary.html')
        except Exception as e1:
            print(f"Error with direct path: {str(e1)}")
            try:
                # Fallback to with 'templates/' prefix
                return render_template('templates/summary.html')
            except Exception as e2:
                print(f"Error with templates/ prefix: {str(e2)}")
                return "Summary template not found."

    @app.route('/load-home/')
    def load_home():
        debug_template_path('home.html')
        try:
            # Try without 'templates/' prefix first
            return render_template('home.html')
        except Exception as e1:
            print(f"Error with direct path: {str(e1)}")
            try:
                # Fallback to with 'templates/' prefix
                return render_template('templates/home.html')
            except Exception as e2:
                print(f"Error with templates/ prefix: {str(e2)}")
                return "Home template not found."

    @app.route('/mission3/')
    def mission3():
        debug_template_path('mission3.html')
        try:
            # Try without 'templates/' prefix first
            return render_template('mission3.html')
        except Exception as e1:
            print(f"Error with direct path: {str(e1)}")
            try:
                # Fallback to with 'templates/' prefix
                return render_template('mission3/mission3.html')
            except Exception as e2:
                print(f"Error with templates/ prefix: {str(e2)}")
                return "Mission3 template not found."

    # Error handler for 404
    @app.errorhandler(404)
    def not_found(e):
        try:
            return render_template('404.html'), 404
        except Exception as error:
            print(f"Error rendering 404.html: {str(error)}")
            return "404 - Page not found", 404

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)
