from flask import Flask, render_template
import os

# Function to create the Flask app
def create_app():
    # Use the root as template_folder
    app = Flask(__name__, static_folder="/var/www/htmx_website/", template_folder="/var/www/htmx_website/")
    
    # Helper function to render templates with fallback paths
    def render_with_fallback(template_name, fallback_template=None):
        try:
            return render_template(template_name)
        except:
            if fallback_template:
                try:
                    return render_template(fallback_template)
                except:
                    return f"Template '{template_name}' not found."
            return f"Template '{template_name}' not found."
    
    # Route for main website pages
    @app.route('/')
    def index():
        return render_with_fallback('index.html')

    @app.route('/header/')
    def header():
        return render_with_fallback('header.html', 'templates/header.html')

    @app.route('/footer/')
    def footer():
        return render_with_fallback('footer.html', 'templates/footer.html')

    @app.route('/summary/')
    def summary():
        return render_with_fallback('summary.html', 'templates/summary.html')

    @app.route('/load-home/')
    def load_home():
        return render_with_fallback('home.html', 'templates/home.html')

    @app.route('/mission3/')
    def mission3():
        return render_with_fallback('mission3.html', 'mission3/mission3.html')

    # Error handler for 404
    @app.errorhandler(404)
    def not_found(e):
        try:
            return render_template('404.html'), 404
        except:
            return "404 - Page not found", 404

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)
