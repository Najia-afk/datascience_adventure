# Datascience Adventure Portfolio

A unified Data Science portfolio platform that aggregates multiple projects ("missions") into a single, cohesive website. Built with **Flask**, **HTMX**, and **Docker**, it serves as a central hub for showcasing data science work, from static notebooks to full-stack machine learning applications.

## 🌟 Features

*   **Unified Interface**: A single entry point (`datascience-adventure.xyz`) for all projects.
*   **Dynamic Content**: Uses **HTMX** for seamless, single-page-application (SPA) feel without the complexity of React/Vue.
*   **Automated Aggregation**: The `deploy.sh` script automatically clones, processes, and integrates content from separate GitHub repositories ("missions").
*   **Reverse Proxy Architecture**: An Nginx container routes traffic to the main portfolio site and proxies requests to standalone web applications (like Mission 7).
*   **Google OAuth Authentication**: Centralized authentication at the front server level for protected routes (Mission 7 Dashboard).
*   **Resilient Design**: Backend services can be down without affecting the main portfolio - graceful "service unavailable" pages.
*   **SSL/TLS**: Fully configured for HTTPS with Let's Encrypt.

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  datascience_adventure                       │
│              (Nginx + Flask with Google OAuth)               │
│                     Port 80/443                              │
└─────────────────────┬───────────────────────────────────────┘
                      │
      ┌───────────────┼───────────────┬───────────────┐
      │               │               │               │
      ▼               ▼               ▼               ▼
┌───────────┐  ┌───────────┐  ┌─────────────┐  ┌────────────────────┐
│  Static   │  │  /login   │  │ /mission7   │  │ /dashboard_mission7│
│  Content  │  │  (OAuth)  │  │ (notebook)  │  │ (dashboard)        │
│  (2-8)    │  │           │  │             │  │ Protected + mlflow │
└───────────┘  └───────────┘  └─────────────┘  └──────────┬─────────┘
                                                          │
                                                          ▼
                                                 ┌────────────────────┐
                                                 │      mission7      │
                                                 │  (Separate Docker) │
                                                 │  Connected via     │
                                                 │  web_network       │
                                                 └────────────────────┘
```

### Authentication Flow

1. User visits `/dashboard_mission7/` (protected route)
2. Nginx checks auth via internal `/auth/check` endpoint
3. If not authenticated → redirect to `/login`
4. User signs in with Google OAuth
5. On success → redirect back to `/dashboard_mission7/`
6. If Mission 7 dashboard is down → show friendly "Service Unavailable" page

## 🚀 Getting Started

### Prerequisites
*   Docker & Docker Compose
*   Git
*   (Optional) Google OAuth credentials for protected routes

### Local Development

```bash
# Clone the repository
git clone https://github.com/Najia-afk/datascience_adventure.git
cd datascience_adventure

# Start in development mode (no SSL, no external dependencies)
docker compose -f docker-compose.dev.yml up --build

# Access at http://localhost:8080
```

### Production Deployment (Fresh Ubuntu/Lightsail)

```bash
# 1. SSH into your server and run the installation script
curl -fsSL https://raw.githubusercontent.com/Najia-afk/datascience_adventure/main/utils/install_docker_server.sh | bash

# 2. Log out and back in (for Docker group permissions)
exit
# SSH back in

# 3. Configure Google OAuth
cd ~/projects/datascience_adventure

# Option A: Create client_secret.json (download from Google Cloud Console)
# Option B: Create .env file:
cat > .env << EOF
GOOGLE_CLIENT_ID=your_client_id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REDIRECT_URI=https://datascience-adventure.xyz/login
ALLOWED_EMAILS=user1@gmail.com,user2@gmail.com
SECRET_KEY=$(openssl rand -hex 32)
EOF

# 4. Start Mission 7 first (if using)
cd ~/projects/mission7
docker compose -f docker-compose.prod.yml up -d --build
~/projects/connect_mission7_network.sh

# 5. Start the main portfolio
cd ~/projects/datascience_adventure
docker compose up -d --build

# 6. (Optional) Set up HTTPS
./utils/setup_https.sh
```

## 🔐 Google OAuth Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable "Google+ API" or "Google Identity"
4. Go to "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
5. Set authorized redirect URI: `https://your-domain.com/login`
6. Download `client_secret.json` and place in project root

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GOOGLE_CLIENT_ID` | OAuth Client ID | (from client_secret.json) |
| `GOOGLE_CLIENT_SECRET` | OAuth Client Secret | (from client_secret.json) |
| `GOOGLE_REDIRECT_URI` | OAuth callback URL | `https://datascience-adventure.xyz/login` |
| `ALLOWED_EMAILS` | Comma-separated whitelist | (empty = allow all) |
| `SECRET_KEY` | Flask session secret | (change in production!) |

## 🔧 Operations

### Adding a New Mission (Static)

1. Edit `utils/deploy.sh`: Add repository URL to the `REPOS` list
2. Rebuild: `docker compose up -d --build`

### Connecting a New Backend Service

1. Start the service in its own Docker Compose
2. Connect to web_network: `docker network connect web_network <container_name>`
3. Add proxy location in `nginx/nginx-docker.conf`
4. Restart nginx: `docker compose restart nginx`

### Updating Content

```bash
cd ~/projects/datascience_adventure
git pull
docker compose up -d --build
```

## 📂 Project Structure

```
.
├── app/
│   ├── server.py           # Flask app with OAuth routes
│   └── static/
│       └── templates/
│           ├── login.html              # Google OAuth login page
│           └── service_unavailable.html # Graceful error page
├── nginx/
│   ├── nginx-docker.conf   # Production config (SSL + auth)
│   └── nginx-dev.conf      # Development config (no SSL)
├── utils/
│   ├── install_docker_server.sh  # Fresh server setup
│   ├── deploy.sh                 # Content deployment
│   └── setup_https.sh            # Let's Encrypt setup
├── docker-compose.yml      # Production
├── docker-compose.dev.yml  # Local development
├── Dockerfile
├── requirements.txt
└── client_secret.json      # (gitignored) Google OAuth credentials
```

## 🛠 Technologies

*   **Frontend**: HTML5, CSS3, HTMX
*   **Backend**: Python, Flask, Gunicorn
*   **Authentication**: Google OAuth 2.0
*   **Infrastructure**: Docker, Nginx, Bash Scripting
*   **SSL**: Let's Encrypt / Certbot

## � Mission 7 Integration (Protected Dashboard)

Mission 7 is a credit scoring MLOps platform that runs as a separate Docker stack but is accessed **only through this proxy** with Google OAuth authentication.

### Architecture
```
datascience_adventure (nginx)                    mission7 (separate docker-compose)
        │                                                │
        │  /dashboard_mission7/* ────────────────────►  nginx:80 (internal only)
        │  (auth_request → /auth/check)                  │
        │                                                ├── api:8000
        │  /dashboard_mission7/mlflow/* ─────────────►  mlflow:5002
        │                                                │
        └── Connected via 'web_network' ─────────────────┘
```

### Security Features
- **No direct port exposure**: Mission7 nginx only uses `expose: 80`, not `ports:`
- **Authentication required**: All `/dashboard_mission7/*` routes require Google OAuth
- **Referer-based routing**: API calls from the dashboard iframe are detected and proxied correctly

### URLs
| Route | Description |
|-------|-------------|
| `/dashboard_mission7/` | Main dashboard (protected) |
| `/dashboard_mission7/predict` | Credit prediction |
| `/dashboard_mission7/api/docs` | Swagger API documentation |
| `/dashboard_mission7/mlflow/` | MLflow experiment tracking |

### Deployment
```bash
# 1. Start mission7 first
cd ~/projects/mission7
docker compose -f docker-compose.prod.yml up -d --build

# 2. Ensure both on same network
docker network create web_network 2>/dev/null || true
docker network connect web_network mission7_nginx_prod
docker network connect web_network mission7_mlflow_prod

# 3. Start datascience_adventure
cd ~/projects/datascience_adventure
docker compose up -d --build
```

## �📝 Notes

- **Resilience**: The front server never goes down if backend services (Mission 7) are unavailable
- **1GB RAM Servers**: The install script automatically creates 2GB swap space
- **Network Isolation**: Mission 7 runs in its own Docker Compose but connects to `web_network` for proxying
