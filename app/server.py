from flask import Flask, render_template_string

app = Flask(__name__)

@app.route("/")
def index():
    # Serve the main index.html file
    return app.send_static_file('index.html')

@app.route("/load-introduction")
def load_introduction():
    content = """
    <div class="article">
        <h2>Introduction</h2>
        <p>This section introduces you to the key principles of data science and the types of projects you can expect to see in this portfolio.</p>
    </div>
    """
    return render_template_string(content)

@app.route("/load-project-1")
def load_project_1():
    content = """
    <div class="article">
        <h2>Project 1: Data Analysis with Pandas</h2>
        <p>A deep dive into analyzing large datasets using Python's pandas library, including data cleaning, transformation, and visualization.</p>
    </div>
    """
    return render_template_string(content)

@app.route("/load-project-2")
def load_project_2():
    content = """
    <div class="article">
        <h2>Project 2: Machine Learning with Scikit-Learn</h2>
        <p>This project focuses on building predictive models using various machine learning algorithms in Python, from linear regression to random forests.</p>
    </div>
    """
    return render_template_string(content)

@app.route("/load-project-3")
def load_project_3():
    content = """
    <div class="article">
        <h2>Project 3: Deep Learning with TensorFlow</h2>
        <p>Explore the exciting world of deep learning by building neural networks to solve complex tasks like image classification and natural language processing.</p>
    </div>
    """
    return render_template_string(content)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
