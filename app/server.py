from flask import Flask, render_template, send_from_directory, abort, request, jsonify, session
import os
import re
import json
import requests
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests

# ===== Google OAuth Configuration =====
def load_google_credentials():
    """Load Google OAuth credentials from client_secret.json file."""
    credentials = {
        'client_id': '',
        'client_secret': '',
        'redirect_uri': os.environ.get('GOOGLE_REDIRECT_URI', 'http://localhost:8080')
    }
    
    # Try to load from client_secret.json (mounted volume in Docker)
    secret_paths = [
        '/app/client_secret.json',
        os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'client_secret.json'),
        'client_secret.json'
    ]
    
    for secret_path in secret_paths:
        if os.path.exists(secret_path):
            try:
                with open(secret_path, 'r') as f:
                    data = json.load(f)
                    # Handle Google's client_secret format (has 'web' or 'installed' key)
                    if 'web' in data:
                        credentials['client_id'] = data['web'].get('client_id', '')
                        credentials['client_secret'] = data['web'].get('client_secret', '')
                    elif 'installed' in data:
                        credentials['client_id'] = data['installed'].get('client_id', '')
                        credentials['client_secret'] = data['installed'].get('client_secret', '')
                    else:
                        # Direct format
                        credentials['client_id'] = data.get('client_id', '')
                        credentials['client_secret'] = data.get('client_secret', '')
                    print(f"Loaded Google credentials from {secret_path}")
                    break
            except Exception as e:
                print(f"Error loading {secret_path}: {e}")
    
    # Override with environment variables if set
    if os.environ.get('GOOGLE_CLIENT_ID'):
        credentials['client_id'] = os.environ['GOOGLE_CLIENT_ID']
    if os.environ.get('GOOGLE_CLIENT_SECRET'):
        credentials['client_secret'] = os.environ['GOOGLE_CLIENT_SECRET']
    
    return credentials

GOOGLE_CREDENTIALS = load_google_credentials()
GOOGLE_CLIENT_ID = GOOGLE_CREDENTIALS['client_id']
GOOGLE_CLIENT_SECRET = GOOGLE_CREDENTIALS['client_secret']
GOOGLE_REDIRECT_URI = GOOGLE_CREDENTIALS['redirect_uri']

# Comma-separated list of allowed emails. If empty, all Google accounts allowed.
ALLOWED_EMAILS = [e.strip() for e in os.environ.get("ALLOWED_EMAILS", "").split(",") if e.strip()]

# Function to create the Flask app
def create_app():
    # Define the base directory relative to this file
    base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static')

    # Determine where the content (processed missions, converted python files) is located
    # In Docker, this is /var/www/htmx_website
    # Locally, we default to the static folder (though content might not be there if not generated)
    if os.path.exists('/var/www/htmx_website'):
        content_dir = '/var/www/htmx_website'
    else:
        content_dir = base_dir

    # Use the root as template_folder
    app = Flask(__name__, static_folder=content_dir, template_folder=content_dir)
    app.config['CONTENT_DIR'] = content_dir
    
    # Session configuration for Google OAuth
    app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
    
    # Allow routes to match with or without trailing slashes
    app.url_map.strict_slashes = False

    # Route for serving converted script HTML files
    @app.route('/<path:repo>_src/<path:filename>')
    def serve_script_html(repo, filename):
        src_dir = os.path.join(app.config['CONTENT_DIR'], f"{repo}_src")
        return send_from_directory(src_dir, filename)
    
    # Route for main website pages
    @app.route('/')
    def index():
        return render_template('index.html')


    @app.route('/header')
    def header():
        return render_template('templates/header.html')


    @app.route('/footer')
    def footer():
        return render_template('templates/footer.html')

    @app.route('/summary')
    def summary():
        return render_template('templates/summary.html')

    @app.route('/load-home')
    def load_home():
        return render_template('templates/home.html')

    @app.route('/contact')
    def contact():
        return render_template('templates/contact.html')

    @app.route('/dashboard/home-credit')
    def dashboard_home_credit():
        return render_template('templates/dashboard_home_credit.html')
    
    # Dynamic route for mission pages
    @app.route('/<path:mission_path>')
    def mission_page(mission_path):
        return render_template(f'{mission_path}.html')

    # Dynamic route for mission content HTML files
    @app.route('/<path:mission_path>_content.html')
    def mission_content(mission_path):
        content_file = f'{mission_path}_content.html'
        # Use the configured content directory
        content_dir = app.config['CONTENT_DIR']
        file_path = os.path.join(content_dir, content_file)
        if os.path.exists(file_path):
            return send_from_directory(content_dir, content_file)
        abort(404)

    # Generic route for static files - properly fixed version
    @app.route('/<path:filename>.py/')
    def serve_static(filename):
        # Clean up the filename - ensure trailing slashes are removed
        filename = re.sub(r'/+', '/', filename).rstrip('/')
        
    
        base_name, ext = os.path.splitext(filename)
        html_filename = base_name + '.html'
        content_dir = app.config['CONTENT_DIR']
        html_path = os.path.join(content_dir, html_filename)
        
        if os.path.exists(html_path):
            return send_from_directory(content_dir, html_filename)
        
        # If not found, return 404
        abort(404)

    # ===== Google OAuth Routes =====
    
    @app.route('/auth/google/login', methods=['POST'])
    def auth_google_login():
        """Exchange Google OAuth code for tokens and create session."""
        code = request.json.get('code')
        if not code:
            return jsonify({'error': 'No code provided'}), 400
        
        try:
            # Exchange code for tokens
            token_url = "https://oauth2.googleapis.com/token"
            payload = {
                'code': code,
                'client_id': GOOGLE_CLIENT_ID,
                'client_secret': GOOGLE_CLIENT_SECRET,
                'redirect_uri': GOOGLE_REDIRECT_URI,
                'grant_type': 'authorization_code'
            }
            res = requests.post(token_url, json=payload)
            token_data = res.json()
            
            if 'error' in token_data:
                return jsonify({'error': token_data['error']}), 400
                
            id_token_str = token_data.get('id_token')
            
            # Verify ID token
            id_info = id_token.verify_oauth2_token(
                id_token_str, google_requests.Request(), GOOGLE_CLIENT_ID
            )
            
            email = id_info.get('email')
            if ALLOWED_EMAILS and email not in ALLOWED_EMAILS:
                print(f"Access denied for email: {email}")
                return jsonify({'error': 'Access denied: Email not authorized'}), 403

            session['user_id'] = id_info['sub']
            session['email'] = email
            session['name'] = id_info.get('name')
            session['token'] = id_token_str
            
            return jsonify({'status': 'success', 'user': session['name']})
        except Exception as e:
            print(f"Auth error: {e}")
            return jsonify({'error': str(e)}), 500

    @app.route('/auth/logout', methods=['POST'])
    def auth_logout():
        """Clear user session."""
        session.clear()
        return jsonify({'status': 'success'})

    @app.route('/auth/check')
    def auth_check():
        """Check if user is authenticated. Used by nginx auth_request."""
        if 'user_id' in session:
            return 'OK', 200
        return 'Unauthorized', 401
    
    @app.route('/auth/user')
    def auth_user():
        """Return current user info."""
        if 'user_id' in session:
            return jsonify({
                'authenticated': True,
                'name': session.get('name'),
                'email': session.get('email')
            })
        return jsonify({'authenticated': False})

    @app.route('/login')
    def login_page():
        """Serve the login page."""
        return render_template('templates/login.html', google_client_id=GOOGLE_CLIENT_ID)

    @app.route('/service-unavailable')
    def service_unavailable():
        """Serve the service unavailable page."""
        return render_template('templates/service_unavailable.html'), 503

    # Error handler for 404
    @app.errorhandler(404)
    def not_found(e):
        return render_template('404.html'), 404

    return app

if __name__ == "__main__":
    # Run the app
    app = create_app()
    app.run(host='0.0.0.0', port=8000)

