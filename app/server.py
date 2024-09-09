from flask import Flask, render_template

app = Flask(__name__, 
            static_folder="/var/www/htmx_website/", 
            template_folder="/var/www/htmx_website/")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/header')
def header():
    return render_template('templates/header.html')

@app.route('/scroll-left')
def scroll_left():
    # HTMX will handle the scroll action on the front-end
    return ""

@app.route('/scroll-right')
def scroll_right():
    # HTMX will handle the scroll action on the front-end
    return ""

@app.route('/footer')
def footer():
    return render_template('templates/footer.html')

@app.route('/summary')
def summary():
    return render_template('templates/summary.html')

@app.route('/load-home')
def load_home():
    return render_template('templates/home.html')

@app.route('/mission3')
def mission3():
    return render_template('mission3/mission3.html')

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=8000)

