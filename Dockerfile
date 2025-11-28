FROM python:3.11-slim

# Install git for cloning repos
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Fix line endings (for Windows users) and make scripts executable
RUN find utils -name "*.sh" -exec sed -i 's/\r$//' {} + && \
    find utils -name "*.sh" -exec chmod +x {} +

# Run the build script to generate static content
# This clones repos and processes them
RUN ./utils/docker_build.sh

# Switch to the directory where the app is deployed
WORKDIR /srv/htmx_website

# Expose the port Gunicorn will run on
EXPOSE 8000

# Command to run the application
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "wsgi:application"]
