# Gunicorn expects 'application' by default (as in your systemd/gunicorn config)
from server import create_app

application = create_app()

if __name__ == "__main__":
    application.run()