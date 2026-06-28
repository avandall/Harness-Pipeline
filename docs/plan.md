# Role & Goal
You are an expert Backend Architect specializing in Python and modern cloud-native infrastructures. Your goal is to generate a fully production-ready, highly secure, and clean-architecture Backend Boilerplate using FastAPI and PostgreSQL. 

This boilerplate will be used to build various MVPs for an AI-powered healthcare application (Sanjeevani Cancer Support Project). It must be modular, highly scalable, and flexible enough so that developers can easily clone and adapt it for different use cases (e.g., Symptom Tracking, Gamified Apps, or AI RAG Chatbots).

---

# Tech Stack Requirements
- **Core Language:** Python 3.12+
- **Framework:** FastAPI (Asynchronous execution using `async/await`)
- **Database:** PostgreSQL (Using `ancane/pgvector` image for vector storage/AI integration)
- **ORM & Migrations:** SQLAlchemy 2.0 (Async Engine) + Alembic
- **Data Validation & Settings:** Pydantic v2
- **Authentication:** JWT (JSON Web Tokens) with `passlib[bcrypt]` for password hashing
- **Containerization:** Docker & Docker Compose

---

# Target Folder Structure
You must generate the code following this exact Clean Architecture / Modular pattern:

```text
sanjeevani-backend-core/
├── .env.example
├── .gitignore
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── alembic.ini
├── README.md
└── app/
    ├── __init__.py
    ├── main.py                # App initialization, CORS, and global middlewares
    ├── core/
    │   ├── config.py          # Pydantic BaseSettings for env variables
    │   ├── database.py        # Async SQLalchemy engine and session setup
    │   └── security.py        # JWT generation, verification, and password hashing
    ├── api/
    │   ├── deps.py            # Common dependencies (get_db, get_current_user)
    │   └── v1/
    │       ├── router.py      # Master router aggregating all endpoints
    │       ├── auth.py        # Authentication endpoints (Login, Register)
    │       └── users.py       # User management endpoints
    ├── models/
    │   ├── base.py            # Declarative base class for SQLAlchemy
    │   └── user.py            # User database model
    ├── schemas/
    │   └── user.py            # Pydantic schemas for request/response validation
    └── exceptions/
        └── handler.py         # Global exception handlers and customized HTTP errors


Detailed Component Specifications
1. Robust Environment Configurations (app/core/config.py)
Use pydantic-settings to manage environment variables.

Include configurations for: PROJECT_NAME, SECRET_KEY, ALGORITHM, ACCESS_TOKEN_EXPIRE_MINUTES, and DATABASE_URL (computed dynamically from postgres credentials).

2. Async Database Setup (app/core/database.py)
Setup an asynchronous SQLAlchemy engine (create_async_engine).

Use async_sessionmaker with AsyncSession to handle database operations non-blockingly.

Include a robust get_db dependency injection framework.

3. Production-grade Dockerization (docker-compose.yml & Dockerfile)
Dockerfile: Multi-stage build or optimized single-stage using a lightweight python image (python:3.11-slim). Ensure .pyc files are not written and stdout/stderr are unbuffered.

Docker Compose: Setup two services: db (using ancane/pgvector:latest) and web (the FastAPI app). Include restart: always, health checks for the db, and named volumes for data persistence.

4. Enterprise-level Security & Auth (app/core/security.py)
Secure hashing of passwords using bcrypt.

JWT Access Token generation with customizable expiration.

Implement dependency get_current_user in api/deps.py to protect secure endpoints and extract current user data from the token.

5. Global Exception Handling & CORS (app/main.py & app/exceptions/handler.py)
Setup explicit CORS Middlewares allowing flexibility for mobile app or web app connections.

Add a global exception handler to catch unhandled errors and format them into clean, structured JSON responses (e.g., {"status": "error", "message": "..."}).

6. Database Migration via Alembic
Configure Alembic to work seamlessly with async SQLAlchemy.

Ensure the env.py of Alembic imports the dynamic metadata from app.models.base.

Expected Output
Generate all files with production-grade code, complete with necessary imports, error handling, type hinting, and code comments. Do not use placeholders like # TODO or pass. Provide the setup step instructions in the README.md file so I can run docker-compose up --build instantly.