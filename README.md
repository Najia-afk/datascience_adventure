# Datascience Adventure Portfolio

A unified Data Science portfolio platform that aggregates multiple projects ("missions") into a single, cohesive website. Built with **Flask**, **HTMX**, and **Docker**, it serves as a central hub for showcasing data science work, from static notebooks to full-stack machine learning applications.

## 🌟 Features

*   **Unified Interface**: A single entry point (`datascience-adventure.xyz`) for all projects.
*   **Dynamic Content**: Uses **HTMX** for seamless, single-page-application (SPA) feel without the complexity of React/Vue.
*   **Automated Aggregation**: The `deploy.sh` script automatically clones, processes, and integrates content from separate GitHub repositories ("missions").
*   **Reverse Proxy Architecture**: An Nginx container routes traffic to the main portfolio site and proxies requests to standalone web applications (like the Mission 7 Dashboard).
*   **SSL/TLS**: Fully configured for HTTPS with Let's Encrypt.

## 🏗 Architecture

The platform consists of two main layers:

1.  **The Portfolio Shell (`datascience_adventure`)**:
    *   **App**: A Flask application serving the landing page and static content (converted notebooks, HTML reports).
    *   **Nginx**: The main gateway. It handles SSL termination and routes traffic:
        *   `/` -> Portfolio App
        *   `/mission7/` -> Mission 7 Container (Internal Network)
        *   `/mission7/mlflow/` -> Mission 7 MLflow (Internal Network)

2.  **The Missions**:
    *   **Static Missions (2-6)**: Notebooks and HTML reports are pulled from their respective repos and served as static files.
    *   **Dynamic Missions (7)**: Full-stack apps running in their own Docker containers on the shared `web_network`.

## 🚀 Getting Started

### Prerequisites
*   Docker & Docker Compose
*   Git

### Installation

1.  **Create the Shared Network**:
    ```bash
    docker network create web_network
    ```

2.  **Clone & Run**:
    ```bash
    git clone https://github.com/Najia-afk/datascience_adventure.git
    cd datascience_adventure
    docker-compose up -d --build
    ```
    *Note: The build process will automatically fetch the configured mission repositories.*

## 🔧 Operations

### Adding a New Mission
To add a new project to the portfolio:

1.  **Edit `utils/deploy.sh`**: Add your repository URL to the `REPOS` list.
2.  **Rebuild**: Run `docker-compose up -d --build`.

### Updating Content
To refresh the portfolio with the latest code from all missions:

```bash
cd datascience_adventure
git pull
docker-compose up -d --build
```

## 📂 Project Structure

```
.
├── app/                # Main Flask application
├── nginx/              # Nginx configuration (Reverse Proxy)
├── utils/
│   ├── deploy.sh       # Main deployment script
│   ├── scripts/        # Helper scripts for content processing
│   └── ...
├── docker-compose.yml  # Service definition
└── Dockerfile          # Build definition
```

## 🛠 Technologies
*   **Frontend**: HTML5, CSS3, HTMX
*   **Backend**: Python, Flask
*   **Infrastructure**: Docker, Nginx, Bash Scripting
