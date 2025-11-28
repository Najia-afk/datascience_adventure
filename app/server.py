from flask import Flask, render_template, send_from_directory, abort
import os

def create_app():
    # Set template_folder to current directory (app/) to find missionX.html
    # Set static_folder to 'static' and static_url_path to '' so /styles/ works
    app = Flask(__name__, static_folder="static", static_url_path="", template_folder=".")
    
    @app.route('/')
    def index():
        return render_template('templates/index.html')

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
    
    @app.route('/<path:mission_path>/')
    def mission_page(mission_path):
        # Security check
        if '..' in mission_path or mission_path.startswith('/'):
             abort(404)
        return render_template(f'{mission_path}.html')

    @app.route('/<path:mission_path>_content.html')
    def mission_content(mission_path):
        if '..' in mission_path or mission_path.startswith('/'):
             abort(404)
        return send_from_directory('.', f'{mission_path}_content.html')

    @app.errorhandler(404)
    def not_found(e):
        return render_template('templates/404.html'), 404

    return app

if __name__ == "__main__":
    app = create_app()
    app.run(host='0.0.0.0', port=8000, debug=True)

