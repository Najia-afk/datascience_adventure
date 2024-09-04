from flask import Flask, render_template_string

app = Flask(__name__)

@app.route("/")
def index():
    # Serve the main index.html file
    return app.send_static_file('index.html')

@app.route("/load-datascientist-training-project-3")
def load_project_3():
    content = """
    <div class="article">
        <h2>Mission 3: Dataset exploration for a public health agency</h2>
        <p>The Public Health Agency wishes to improve the quality of Open Food Facts data, an open source database is made available to individuals and organizations to allow them to know the nutritional quality of products.</p>
        <a href="/mission3/mission3.html" target="_blank">Go to mission 3</a>
    </div>
    """
    return render_template_string(content)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
