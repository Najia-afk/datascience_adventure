from server import create_app

# Create the Flask application
application = create_app()

# For gunicorn to find the application
app = application

if __name__ == "__main__":
    application.run()