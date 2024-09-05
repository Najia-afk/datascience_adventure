from flask import Flask, render_template_string, send_from_directory, abort

app = Flask(__name__, static_folder="/var/www/htmx_website/")

@app.route("/")
def index():
    # Serve the main index.html file
    return app.send_static_file('index.html')

@app.route("/mission3")
def load_project_3():
    # Serve the mission3.html file for the clean URL
    return app.send_static_file('mission3/mission3.html')

@app.route("/mission3/scripts/<path:filename>")
def serve_scripts(filename):
    # Serve HTML files from the 'scripts' directory within 'mission3'
    try:
        return send_from_directory('mission3/scripts', filename)
    except FileNotFoundError:
        abort(404)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
