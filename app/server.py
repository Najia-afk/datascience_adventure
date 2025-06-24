from flask import Flask, render_template

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
        try:
            # Try without 'templates/' prefix first
            return render_template('header.html')
        except:
            # Fallback to with 'templates/' prefix
            return render_template('templates/header.html')

    @app.route('/footer/')
    def footer():
        try:
            # Try without 'templates/' prefix first
            return render_template('footer.html')
        except:
            # Fallback to with 'templates/' prefix
            return render_template('templates/footer.html')

    @app.route('/summary/')
    def summary():
        try:
            # Try without 'templates/' prefix first
            return render_template('summary.html')
        except:
            # Fallback to with 'templates/' prefix
            return render_template('templates/summary.html')

    @app.route('/load-home/')
    def load_home():
        try:
            # Try without 'templates/' prefix first
            return render_template('home.html')
        except:
            # Fallback to with 'templates/' prefix
            return render_template('templates/home.html')

    @app.route('/mission3/')
    def mission3():
        try:
            # Try without 'templates/' prefix first
            return render_template('mission3.html')
        except:
            # Fallback to with 'templates/' prefix
            return render_template('mission3/mission3.html')

    # Error handler for 404
    @app.errorhandler(404)
    def not_found(e):
        return render_template('404.html'), 404

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)
