from flask import Flask, render_template, jsonify

app = Flask(__name__, 
            static_folder="/var/www/htmx_website/", 
            template_folder="/var/www/htmx_website/")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/header/')
def header():
    return render_template('templates/header.html')

@app.route('/scroll-left/')
def scroll_left():
    # Return a negative scroll distance for left scrolling
    return jsonify({'scroll_distance': -320})

@app.route('/scroll-right/')
def scroll_right():
    # Return a positive scroll distance for right scrolling
    return jsonify({'scroll_distance': 320})

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

@app.errorhandler(404)
def not_found(e):
    return render_template('404.html'), 404

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=8000)

