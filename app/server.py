from flask import Flask, render_template

app = Flask(__name__, static_folder="/var/www/htmx_website/")


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


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
