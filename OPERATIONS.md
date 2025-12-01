# Server Operations Cheat Sheet

## 1. Install from Scratch
Run these commands to set up the server for the first time.

```bash
# 1. Create the shared network
docker network create web_network

# 2. Start the Main Website
cd datascience_adventure
docker-compose up -d --build

# 3. Start the Dashboard (Mission 7)
cd ../mission7
docker-compose up -d --build
```

## 2. Update Main Website
Run this to update the landing page or fetch the latest notebooks from all missions.

```bash
cd datascience_adventure
git pull
docker-compose up -d --build
```

## 3. Update Webapp (Mission 7)
Run this to update the dashboard code or configuration.

```bash
cd mission7
git pull
docker-compose up -d --build
```

## 4. Integrate New App
*   **Static Content (Notebooks):** 
    1. Add the repo URL to `datascience_adventure/utils/deploy.sh`.
    2. Run **Update Main Website** (Step 2).
*   **Dynamic App (Server):** 
    1. Add a new `location` block to `datascience_adventure/nginx/nginx-docker.conf`.
    2. Run `docker-compose restart nginx`.
