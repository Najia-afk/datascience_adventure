from server import create_app

# Create the Flask-Dash application
application = create_app()

if __name__ == "__main__":
    application.run()