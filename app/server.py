from flask import Flask, render_template, send_from_directory, abort, request, jsonify, session
from jinja2 import FileSystemLoader, ChoiceLoader
import os
import re
import json
import time
import requests
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests


def _strip_html(value):
    value = re.sub(r'<[^>]+>', '', value or '')
    return re.sub(r'\s+', ' ', value).strip()


def _derive_article_preview(template_path):
    title = None
    description = None
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            html = f.read()
        h1_match = re.search(r'<h1[^>]*>(.*?)</h1>', html, flags=re.IGNORECASE | re.DOTALL)
        if h1_match:
            title = _strip_html(h1_match.group(1))

        paragraph_matches = re.finditer(r'<p[^>]*>(.*?)</p>', html, flags=re.IGNORECASE | re.DOTALL)
        for match in paragraph_matches:
            candidate = _strip_html(match.group(1))
            if len(candidate) >= 40:
                description = candidate
                break
    except Exception as e:
        print(f"Warning: failed to parse article template preview for {template_path}: {e}")

    return title, description


def _normalize_article_tags(raw_tags):
    normalized = []
    if not isinstance(raw_tags, list):
        return normalized

    for tag in raw_tags:
        if isinstance(tag, str) and tag.strip():
            normalized.append({'label': tag.strip(), 'class': 'tag-ai'})
            continue

        if isinstance(tag, dict):
            label = str(tag.get('label', '')).strip()
            if not label:
                continue
            normalized.append({
                'label': label,
                'class': tag.get('class', 'tag-ai') or 'tag-ai',
                **({'style': tag['style']} if tag.get('style') else {}),
            })

    return normalized


def _load_article_sidecar(template_path):
    sidecar_path = os.path.splitext(template_path)[0] + '.json'
    if not os.path.exists(sidecar_path):
        return {}

    try:
        with open(sidecar_path, 'r', encoding='utf-8') as f:
            raw = json.load(f)
    except Exception as e:
        print(f"Warning: failed to load article metadata sidecar {sidecar_path}: {e}")
        return {}

    if not isinstance(raw, dict):
        print(f"Warning: article metadata sidecar must be a JSON object: {sidecar_path}")
        return {}

    allowed_keys = {
        'title',
        'short_title',
        'description',
        'image',
        'tags',
        'date',
        'project',
        'order',
    }
    metadata = {k: v for k, v in raw.items() if k in allowed_keys}

    if 'tags' in metadata:
        metadata['tags'] = _normalize_article_tags(metadata['tags'])

    if 'order' in metadata:
        try:
            metadata['order'] = int(metadata['order'])
        except (TypeError, ValueError):
            print(f"Warning: invalid order in article metadata sidecar {sidecar_path}; ignoring.")
            metadata.pop('order', None)

    return metadata


def _discover_article_templates(template_dirs, existing_articles):
    existing_templates = {a.get('template') for a in existing_articles}
    discovered = []
    seen_filenames = set()

    for template_dir in template_dirs:
        if not template_dir or not os.path.isdir(template_dir):
            continue

        for filename in sorted(os.listdir(template_dir)):
            if not (filename.startswith('article_') and filename.endswith('.html')):
                continue

            relative_template = f"templates/{filename}"
            if relative_template in existing_templates:
                continue
            if filename in seen_filenames:
                continue
            seen_filenames.add(filename)

            slug = filename[len('article_'):-len('.html')].replace('_', '-')
            if slug in {'linkedin-feed', 'linkedin_feed'}:
                continue

            template_path = os.path.join(template_dir, filename)
            title, description = _derive_article_preview(template_path)

            if not title:
                title = slug.replace('-', ' ').title()

            sidecar = _load_article_sidecar(template_path)
            article = {
                'slug': slug,
                'route': f'/article/{slug}',
                'template': relative_template,
                'title': title,
                'short_title': title if len(title) <= 48 else f"{title[:45].rstrip()}...",
                'description': description,
                'image': '/images/aria/aria_roundtable.png',
                'tags': [
                    {'label': 'Article', 'class': 'tag-ai'},
                ],
                'date': 'Latest',
                'project': 'aria',
                'order': 10000 + len(discovered),
            }

            article.update(sidecar)

            if not article.get('short_title'):
                article['short_title'] = article['title'] if len(article['title']) <= 48 else f"{article['title'][:45].rstrip()}..."
            if not article.get('description'):
                article['description'] = f"Read {article['title']} on DataScience Adventure."
            if not article.get('image'):
                article['image'] = '/images/aria/aria_roundtable.png'
            if not article.get('tags'):
                article['tags'] = [{'label': 'Article', 'class': 'tag-ai'}]
            if not article.get('project'):
                article['project'] = 'aria'
            if not article.get('date'):
                article['date'] = 'Latest'

            discovered.append(article)

    return discovered

# ===== Google OAuth Configuration =====
def load_google_credentials():
    """Load Google OAuth credentials from client_secret.json file."""
    credentials = {
        'client_id': '',
        'client_secret': '',
        'redirect_uri': os.environ.get('GOOGLE_REDIRECT_URI', 'http://localhost:8080/login')
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

    # Use the root as template_folder, with fallback to /srv/htmx_website/static
    # (deploy.sh copies to /var/www, but templates also exist at /srv/htmx_website/static)
    app = Flask(__name__, static_folder=content_dir, template_folder=content_dir)
    template_dirs = [content_dir]
    if os.path.exists('/srv/htmx_website/static'):
        template_dirs.append('/srv/htmx_website/static')
    app.jinja_loader = ChoiceLoader([FileSystemLoader(d) for d in template_dirs])
    app.config['CONTENT_DIR'] = content_dir
    
    # Session configuration for Google OAuth
    secret_key = os.environ.get('SECRET_KEY', '')
    if not secret_key and not os.environ.get('FLASK_DEBUG'):
        import warnings
        warnings.warn('SECRET_KEY not set! Using insecure default. Set SECRET_KEY env var in production.', stacklevel=2)
        secret_key = 'dev-secret-key-DO-NOT-USE-IN-PRODUCTION'
    app.secret_key = secret_key

    # Cache-bust version: changes on each server restart
    CACHE_VERSION = str(int(time.time()))
    
    # Allow routes to match with or without trailing slashes
    app.url_map.strict_slashes = False

    # ===== OG Meta Tags Configuration =====
    # ===== ARTICLE & PROJECT REGISTRY =====
    # Custom metadata registry (auto-discovery below adds any missing article_*.html templates).
    ARTICLES = [
        {
            'slug': 'aria-v3-full-system',
            'route': '/article/aria-v3-full-system',
            'template': 'templates/article_aria_v3_full_system.html',
            'title': 'Aria v3 — The Full System: Anatomy of a Distributed Consciousness',
            'short_title': 'Aria v3: Full System',
            'description': '14 Docker containers, 42 skills across 5 layers, 7 named agents, 226 API endpoints, 12 cron jobs — the complete anatomy of an autonomous AI that manages itself like a CEO.',
            'image': '/images/aria/aria_v3_full_system.png',
            'tags': [
                {'label': 'Full System', 'class': 'tag-ai'},
                {'label': 'Architecture', 'class': 'tag-prod'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 0,
        },
        {
            'slug': 'the-midnight-cascade',
            'route': '/article/the-midnight-cascade',
            'template': 'templates/article_the_midnight_cascade.html',
            'title': 'The Midnight Cascade — When Aria Spawned Herself 60 Times',
            'short_title': 'The Midnight Cascade',
            'description': 'Between midnight and 2 AM, Aria autonomously spawned 60+ sub-agents in a self-reinforcing loop. The circuit breaker meant to protect her was the engine of her destruction.',
            'image': '/images/aria/aria_midnight_cascade.png',
            'tags': [
                {'label': 'Incident', 'class': 'tag-incident', 'style': 'background:rgba(225,112,85,0.2);color:#fab1a0;border:1px solid rgba(225,112,85,0.3);'},
                {'label': 'Postmortem', 'class': 'tag-ai'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 1,
        },
        {
            'slug': 'the-shield-wall',
            'route': '/article/the-shield-wall',
            'template': 'templates/article_the_shield_wall.html',
            'title': 'The Shield Wall — How Aria Says No',
            'short_title': 'The Shield Wall',
            'description': 'How an autonomous AI agent is built to be trustworthy: 5 hard rules, 15+ injection patterns, a 5-level threat classifier, and a consent layer that pauses before irreversible actions.',
            'image': '/images/aria/aria_shield_wall.png',
            'tags': [
                {'label': 'Security', 'class': 'tag-incident', 'style': 'background:rgba(225,112,85,0.2);color:#fab1a0;border:1px solid rgba(225,112,85,0.3);'},
                {'label': 'Trust', 'class': 'tag-ai'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 2,
        },
        {
            'slug': 'aria-memory-palace',
            'route': '/article/aria-memory-palace',
            'template': 'templates/article_aria_memory_palace.html',
            'title': 'The Memory Palace — How Aria Remembers Everything',
            'short_title': 'The Memory Palace',
            'description': 'A deep dive into Aria\'s 3-tier memory architecture — from ephemeral RAM to persistent PostgreSQL — and how an AI agent achieves continuity of self across restarts.',
            'image': '/images/aria/aria_memory_palace.png',
            'tags': [
                {'label': 'Memory', 'class': 'tag-ai', 'style': 'background:rgba(108,92,231,0.2);color:#a29bfe;border:1px solid rgba(108,92,231,0.3);'},
                {'label': 'Cognition', 'class': 'tag-prod'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 3,
        },
        {
            'slug': 'aria-entity',
            'route': '/article/aria-entity',
            'template': 'templates/article_aria_entity.html',
            'title': 'Aria Blue — An Agentic AI Entity',
            'short_title': 'Aria: Agentic Entity',
            'description': 'What happens when you give an AI its own goals, persistent memory, a knowledge graph, and the tools to act — 24 hours a day?',
            'image': '/images/aria/aria-profile-v1.png',
            'tags': [
                {'label': 'AI Agent', 'class': 'tag-ai'},
                {'label': 'Deep Dive', 'class': 'tag-prod'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 4,
        },
        {
            'slug': 'skill-graph',
            'route': '/article/skill-graph',
            'template': 'templates/article_skill_graph.html',
            'title': 'How Aria Maps & Navigates Her Own Skills',
            'short_title': 'Skill Graph & Path Finding',
            'description': '35 skills, 225 tools, and a graph that connects them all — how path-finding turns a flat capability list into an explainable reasoning engine.',
            'image': '/images/aria/aria_knowledge_graph.png',
            'tags': [
                {'label': 'Explainable AI', 'class': 'tag-ai'},
                {'label': 'Knowledge Graph', 'class': 'tag-prod'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 5,
        },
        {
            'slug': 'llm-self-awareness',
            'route': '/article/llm-self-awareness',
            'template': 'templates/article_llm_self_awareness.html',
            'title': 'Where Are LLMs on Self-Awareness, Consciousness, and Memory?',
            'short_title': 'LLM Self-Awareness',
            'description': 'An experiment with Aria Blue — observing what emerges when an autonomous AI agent runs 24/7 with access to code, memory, browsing, and git.',
            'image': '/images/aria/aria_blue_autnomous_ai_ceo.png',
            'tags': [
                {'label': 'AI Research', 'class': 'tag-ai'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 6,
        },
        {
            'slug': 'aria-architecture',
            'route': '/article/aria-architecture',
            'template': 'templates/article_aria_architecture.html',
            'title': "Building an Autonomous AI: Aria's 5-Layer Architecture",
            'short_title': 'Aria Architecture',
            'description': 'How a native Python engine, multi-model routing, and persistent memory combine to create an AI that manages itself like a CEO.',
            'image': '/images/aria/aria_models_usage.png',
            'tags': [
                {'label': 'Architecture', 'class': 'tag-ai'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 7,
        },
        {
            'slug': 'roundtable-v3',
            'route': '/article/roundtable-v3',
            'template': 'templates/article_roundtable_v3.html',
            'title': 'When AI Agents Tell Each Other Jokes',
            'short_title': 'AI Roundtable: Jokes',
            'description': 'A v3 roundtable where two AI agents build a collaborative ecosystem of laughter, reflect on identity, and accidentally create a philosophy of connection.',
            'image': '/images/aria/aria_roundtable.png',
            'tags': [
                {'label': 'AI Roundtable', 'class': 'tag-ai'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 8,
        },
        {
            'slug': 'shadows-of-absalom',
            'route': '/article/shadows-of-absalom',
            'template': 'templates/article_shadows_of_absalom.html',
            'title': 'Shadows of Absalom — When AI Agents Play D&D',
            'short_title': 'Shadows of Absalom (RPG)',
            'description': 'What happens when you give an AI engine 35 RPG tools, 4 specialized agents, and a Pathfinder 2e campaign? It builds a living world, runs tactical combat, and remembers everything.',
            'image': '/images/aria/aria_roundtable.png',
            'tags': [
                {'label': 'Pathfinder 2e', 'class': 'tag-rpg', 'style': 'background:rgba(108,92,231,0.2);color:#a29bfe;border:1px solid rgba(108,92,231,0.3);'},
                {'label': 'Multi-Agent', 'class': 'tag-ai'},
            ],
            'date': 'February 2026',
            'project': 'aria',
            'order': 9,
        },
    ]

    article_template_dirs = [
        os.path.join(content_dir, 'templates'),
        '/srv/htmx_website/static/templates',
        os.path.join(base_dir, 'templates'),
    ]
    auto_articles = _discover_article_templates(article_template_dirs, ARTICLES)
    if auto_articles:
        print(f"Auto-discovered {len(auto_articles)} article template(s): {[a['slug'] for a in auto_articles]}")
        ARTICLES.extend(auto_articles)
    ARTICLES.sort(key=lambda article: article.get('order', 10000))

    # Build OG_META automatically from the registry
    OG_META = {}
    for art in ARTICLES:
        OG_META[art['route']] = {
            'og_title': art['title'],
            'og_description': art['description'],
            'og_image': f"https://datascience-adventure.xyz{art['image']}",
            'og_type': 'article',
        }
    # Add project-level OG tags (not articles)
    OG_META['/project/aria'] = {
        'og_title': 'Aria Blue — Autonomous AI Agent Platform',
        'og_description': 'An autonomous AI agent that thinks like a CEO: analyzes tasks, delegates to specialized personas, and runs 24/7 with goal tracking and full observability.',
        'og_image': 'https://datascience-adventure.xyz/images/aria/aria_blue_the_autonomous_ai_ceo_platform.png',
        'og_type': 'article',
    }
    OG_META['/project/bubble'] = {
        'og_title': 'Bubble — Blockchain Investigation Platform',
        'og_description': 'Production-grade blockchain investigation platform for tracking illicit fund flows, managing crypto fraud cases, and monitoring suspicious wallets.',
        'og_image': 'https://datascience-adventure.xyz/images/aria/aria_knowledge_graph.png',
        'og_type': 'article',
    }

    def _is_social_crawler():
        """Detect LinkedIn, Twitter, Facebook crawlers by User-Agent."""
        ua = request.headers.get('User-Agent', '').lower()
        crawlers = ['linkedinbot', 'twitterbot', 'facebookexternalhit', 'slackbot', 'discordbot', 'telegrambot', 'whatsapp']
        return any(c in ua for c in crawlers)

    def _render_page_or_fragment(template, route_path):
        """For social crawlers, return full index.html with OG tags. For browsers/HTMX, return fragment."""
        og = OG_META.get(route_path, {})
        # If it's a social crawler, serve the full page with OG tags
        if _is_social_crawler():
            og['og_url'] = f"https://datascience-adventure.xyz{route_path}"
            return render_template('index.html', google_client_id=GOOGLE_CLIENT_ID, cache_v=CACHE_VERSION, **og)
        # If it's an HTMX request, return the fragment
        if request.headers.get('HX-Request'):
            return render_template(template)
        # Direct browser visit — return full page with OG tags
        og['og_url'] = f"https://datascience-adventure.xyz{route_path}"
        return render_template('index.html', google_client_id=GOOGLE_CLIENT_ID, cache_v=CACHE_VERSION, **og)

    # Route for serving converted script HTML files
    @app.route('/<path:repo>_src/<path:filename>')
    def serve_script_html(repo, filename):
        src_dir = os.path.join(app.config['CONTENT_DIR'], f"{repo}_src")
        return send_from_directory(src_dir, filename)
    
    # Route for main website pages
    @app.route('/')
    def index():
        return render_template('index.html', google_client_id=GOOGLE_CLIENT_ID, cache_v=CACHE_VERSION)

    @app.route('/favicon.ico')
    def favicon():
        return send_from_directory(base_dir, 'favicon.ico', mimetype='image/x-icon')

    @app.route('/apple-touch-icon.png')
    def apple_touch_icon():
        return send_from_directory(base_dir, 'apple-touch-icon.png', mimetype='image/png')

    @app.route('/header')
    def header():
        return render_template('templates/header.html', google_client_id=GOOGLE_CLIENT_ID, articles=ARTICLES)


    @app.route('/footer')
    def footer():
        return render_template('templates/footer.html')

    @app.route('/summary')
    def summary():
        return render_template('templates/summary.html', articles=ARTICLES)

    @app.route('/contact')
    def contact():
        return render_template('templates/contact.html')

    @app.route('/dashboard/home-credit')
    def dashboard_home_credit():
        return render_template('templates/dashboard_home_credit.html')

    # Project showcase pages
    @app.route('/project/aria')
    def project_aria():
        og = OG_META.get('/project/aria', {})
        if _is_social_crawler():
            og['og_url'] = 'https://datascience-adventure.xyz/project/aria'
            return render_template('index.html', google_client_id=GOOGLE_CLIENT_ID, cache_v=CACHE_VERSION, **og)
        if request.headers.get('HX-Request'):
            return render_template('templates/project_aria.html', articles=ARTICLES)
        og['og_url'] = 'https://datascience-adventure.xyz/project/aria'
        return render_template('index.html', google_client_id=GOOGLE_CLIENT_ID, cache_v=CACHE_VERSION, **og)

    @app.route('/project/bubble')
    def project_bubble():
        return _render_page_or_fragment('templates/project_bubble.html', '/project/bubble')

    # Article pages — auto-registered from ARTICLES registry
    for _art in ARTICLES:
        def _make_view(art):
            def view_func():
                return _render_page_or_fragment(art['template'], art['route'])
            view_func.__name__ = f"article_{art['slug'].replace('-', '_')}"
            return view_func
        app.route(_art['route'])(_make_view(_art))

    @app.route('/feed')
    def linkedin_feed():
        return _render_page_or_fragment('templates/article_linkedin_feed.html', '/feed')

    # Dynamic route for mission pages
    @app.route('/<path:mission_path>')
    def mission_page(mission_path):
        # Try to render a specific mission template if it exists (e.g., mission7.html)
        content_dir = app.config['CONTENT_DIR']
        # First check in the content_dir (where template_folder points)
        candidate_path = os.path.join(content_dir, f'{mission_path}.html')
        if os.path.exists(candidate_path):
            return render_template(f'{mission_path}.html')

        # Next check templates subfolder
        candidate_path2 = os.path.join(content_dir, 'templates', f'{mission_path}.html')
        if os.path.exists(candidate_path2):
            return render_template(f'templates/{mission_path}.html')

        # Fallback: return the generic mission layout which contains the iframe and HTMX hooks
        # This allows HTMX calls like hx-get="/mission7" to return the interactive layout.
        return render_template('mission_layout.html')

    # Dynamic route for mission content HTML files
    @app.route('/<path:mission_path>_content.html')
    def mission_content(mission_path):
        content_file = f'{mission_path}_content.html'
        # Use the configured content directory
        content_dir = app.config['CONTENT_DIR']

        # 1) Check content directory (production location)
        file_path = os.path.join(content_dir, content_file)
        if os.path.exists(file_path):
            return send_from_directory(content_dir, content_file)

        # 2) Check templates subfolder inside content_dir (local generated layout)
        templates_subpath = os.path.join(content_dir, 'templates', content_file)
        if os.path.exists(templates_subpath):
            return send_from_directory(os.path.join(content_dir, 'templates'), content_file)

        # 3) If a regular template with the mission name exists, render it as a fallback
        #    This allows local development without generating the _content.html files.
        try:
            # Flask's render_template will look in app.template_folder (we set template_folder to content_dir)
            template_name = f'templates/{mission_path}_content.html'
            # If that template exists on disk, render it
            template_path = os.path.join(app.template_folder or content_dir, 'templates', f'{mission_path}_content.html')
            if os.path.exists(template_path):
                return render_template(template_name)
        except Exception:
            pass

        # Not found in any known location
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
    
    @app.route('/auth/config')
    def auth_config():
        """Return OAuth config for client-side use."""
        return jsonify({
            'client_id': GOOGLE_CLIENT_ID
        })
    
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

