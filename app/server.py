from flask import Flask, render_template

# Function to create the Flask app
def create_app():
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

    @app.route('/mission3/')
    def mission3():
        return render_template('mission3/mission3.html')

    @app.route('/mission3/Mission3.html')
    def mission3_notebook():
        return render_template('mission3/Mission3.html')

    # Route to embed NutriScore Dash app
    @app.route('/mission3/nutriscore')
    def mission3_nutriscore():
        return render_template('dash_app.html', dash_app_url="/mission3/nutriscore/")

    # Route to embed Cluster Dash app
    @app.route('/mission3/cluster')
    def mission3_cluster():
        return render_template('dash_app.html', dash_app_url="/mission3/cluster/")

    # Error handler for 404
    @app.errorhandler(404)
    def not_found(e):
        return render_template('404.html'), 404

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)
