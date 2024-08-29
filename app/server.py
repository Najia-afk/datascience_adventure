# app/server.py
from flask import Flask, request

app = Flask(__name__, static_folder='static', static_url_path='')

@app.route('/')
def index():
    return app.send_static_file('index.html')

@app.route('/hello')
def hello():
    return '<p>Hello from HTMX!</p>'

@app.route('/load-content')
def load_content():
    return '<p>This is dynamically loaded content using HTMX!</p>'

@app.route('/submit-feedback', methods=['POST'])
def submit_feedback():
    name = request.form.get('name')
    feedback = request.form.get('feedback')
    response = f"<p>Thank you, {name}, for your feedback: \"{feedback}\"</p>"
    return response

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
