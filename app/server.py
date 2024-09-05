from flask import Flask, render_template_string, send_from_directory

app = Flask(__name__, static_folder="/var/www/htmx_website")

@app.route("/")
def index():
    # Serve the main index.html file
    return app.send_static_file('index.html')

@app.route("/project/mission3")
def load_project_3():
    # Serve the mission3.html file for the clean URL
    return app.send_static_file('mission3/mission3.html')

# Optionally, if you want to handle HTMX dynamic loading
@app.route("/load-datascientist-training-project-3")
def load_project_3_htmx():
    content = """
    <div class="article">
        <h2>Mission 3: Dataset exploration for a public health agency</h2>
        <p>The Public Health Agency wishes to improve the quality of Open Food Facts data, an open source database is made available to individuals and organizations to allow them to know the nutritional quality of products.</p>
        <a href="/project/mission3">Go to mission 3</a>
    </div>
    """
    return render_template_string(content)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
