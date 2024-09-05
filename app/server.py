from flask import Flask, send_from_directory, abort

app = Flask(__name__, static_folder="/var/www/htmx_website/")

@app.route("/")
def index():
    # Serve the main index.html file
    return app.send_static_file('index.html')

@app.route("/load-home")
def load_home():
    # Serve the main index.html file for HTMX requests
    return app.send_static_file('index.html')

@app.route("/mission3")
def load_mission3():
    # Serve the mission3.html file for HTMX requests
    return app.send_static_file('mission3/mission3.html')

@app.route("/mission3/scripts/<path:filename>")
def serve_scripts(filename):
    # Serve HTML files from the 'scripts' directory within 'mission3'
    try:
        return send_from_directory('mission3/scripts', filename)
    except FileNotFoundError:
        abort(404)

@app.route("/load-contact")
def load_contact():
    # Dummy example for contact page, replace with actual content
    return "<h1>Contact Us</h1><p>Contact details here...</p>"

@app.route("/toggle-dark-mode")
def toggle_dark_mode():
    # Dummy example for dark mode toggle, replace with actual logic
    return "<style>body { background-color: #333; color: #fff; }</style>"

@app.route("/test")
def test():
    return "<p>This is a test response.</p>"

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
