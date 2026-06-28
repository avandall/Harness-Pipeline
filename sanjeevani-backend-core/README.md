# Sanjeevani Backend Core

Production-ready FastAPI boilerplate for Sanjeevani Cancer Support MVPs, built with async SQLAlchemy, PostgreSQL with pgvector, JWT authentication, Alembic migrations, and Docker Compose.

## Features

- FastAPI with async request handling
- PostgreSQL using the `ankane/pgvector` image
- SQLAlchemy 2.0 async ORM and Alembic migrations
- Pydantic v2 settings and request validation
- JWT login with bcrypt password hashing
- Clean modular project layout
- Global structured exception responses
- Docker-first local setup

## Quick Start

1. Create your environment file:

   ```bash
   cp .env.example .env
   ```

2. Start the stack:

   ```bash
   docker compose up --build
   ```

3. Open the API docs:

   ```text
   http://localhost:8000/docs
   ```

The web container runs `alembic upgrade head` automatically before starting the API.

## Useful Commands

Run migrations manually:

```bash
docker compose exec web alembic upgrade head
```

Create a new migration after changing models:

```bash
docker compose exec web alembic revision --autogenerate -m "describe change"
```

Check health:

```bash
curl http://localhost:8000/health
```

## Authentication Flow

Register a user:

```bash
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"StrongPass123","full_name":"Admin User"}'
```

Log in:

```bash
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin@example.com&password=StrongPass123"
```

Use the returned bearer token to call protected routes:

```bash
curl http://localhost:8000/api/v1/users/me \
  -H "Authorization: Bearer <access_token>"
```

## Project Structure

```text
app/
  api/
    deps.py
    v1/
      auth.py
      router.py
      users.py
  core/
    config.py
    database.py
    security.py
  exceptions/
    handler.py
  models/
    base.py
    user.py
  schemas/
    user.py
  main.py
alembic/
  env.py
  versions/
```

## Production Notes

- Replace `SECRET_KEY` before deploying.
- Restrict `BACKEND_CORS_ORIGINS` to trusted domains.
- Use managed secrets instead of plaintext environment files.
- Run behind a TLS-terminating reverse proxy or cloud load balancer.
- Keep migrations reviewed and checked into source control.

