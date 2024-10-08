from flask import Flask, render_template
from dash import Dash, html, dcc
from werkzeug.middleware.dispatcher import DispatcherMiddleware
from werkzeug.serving import run_simple
import pandas as pd
from /var/www/htmx_website/mission3/scripts/plot_nutriscore import create_layout, update_graph_callback, update_nutriscore_legend


app = Flask(__name__, 
            static_folder="/var/www/htmx_website/", 
            template_folder="/var/www/htmx_website/")

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

# Error handler for 404
@app.errorhandler(404)
def not_found(e):
    return render_template('404.html'), 404


# Function to create the Dash application
def create_dash_mission3(flask_app):
    # Load the necessary data
    nutriscore_directory = '/var/www/htmx_website/data/nutrition_combination_log.csv'  # Adjust the path to your data location
    df = pd.read_csv(nutriscore_directory)

    # Create Dash app
    dash_app = Dash(__name__, server=flask_app, url_base_pathname='/mission3/nutriscore/')
    dash_app.layout = create_layout()  # Use the layout from the plot_nutriscore script

    # Set up Dash callbacks (from plot_nutriscore.py)
    dash_app.callback(
        Output('cluster-bubble-chart', 'figure'),
        Output('nutriscore-legend', 'children'),
        [Input('frequency-slider', 'value'), Input('display-options', 'value')]
    )(lambda frequency_threshold, display_options: update_graph_callback(frequency_threshold, display_options, df))

    return dash_app


# Setting up DispatcherMiddleware to mount multiple Dash apps
def create_app():
    # Create Flask app
    flask_app = app

    # Create Dash app and register it
    dash_mission3 = create_dash_mission3(flask_app)

    # Use DispatcherMiddleware to combine Flask and Dash apps
    application = DispatcherMiddleware(flask_app.wsgi_app, {
        '/mission3/nutriscore': dash_mission3.server,  # Mount Dash app
        # You can add more Dash apps here if needed in the future
    })

    return application


if __name__ == "__main__":
    # Run combined Flask and Dash apps
    application = create_app()
    run_simple('0.0.0.0', 8000, application)
