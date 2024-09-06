from flask import Flask, send_from_directory, abort, render_template

app = Flask(__name__, static_folder="/var/www/htmx_website/")

@app.route("/")
def index():
    # Serve the main index.html file
    return app.send_static_file('index.html')

@app.route('/header')
def header():
    return render_template('header.html')

@app.route('/footer')
def footer():
    return render_template('footer.html')

@app.route('/summary')
def summary():
    return render_template('summary.html')

@app.route('/load-home')
def load_home():
    return render_template('home.html')


@app.route('/mission3')
def mission3():
    return render_template('/mission3/mission3.html')

@app.route("/load-contact")
def load_contact():
    # Dummy example for contact page, replace with actual content
    return "<h1>Contact Us</h1><p>Contact details here...</p>"

@app.route("/toggle-dark-mode")
def toggle_dark_mode():
    # Dummy example for dark mode toggle, replace with actual logic
    return "<style>body { background-color: #333; color: #fff; }</style>"


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
