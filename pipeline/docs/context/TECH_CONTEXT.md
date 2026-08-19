# TECH CONTEXT
# Bối cảnh kỹ thuật — Stack, Môi trường và Kiến trúc Kỹ thuật

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** [YYYY-MM-DD]
>
> ✏️ **HUMAN FILLS THIS FILE.** File này quy định chi tiết kỹ thuật, công nghệ, cấu trúc code và API contracts.

---

## 1. Tech Stack & Environment

### Language & Framework
```
Runtime:          [Ví dụ: Python 3.11+ / Node.js 20+ / Go 1.22+]
Framework:        [Ví dụ: FastAPI / Next.js / Express / Gin]
Web Server:       [Ví dụ: Uvicorn / Node runtime / Native]
Validation:       [Ví dụ: Pydantic v2 / Zod / Type validation]
API Protocol:     [Ví dụ: REST API (JSON) / GraphQL / gRPC]
```

### Database & Storage
```
Primary DB:       [Ví dụ: PostgreSQL 15 / SQLite / MongoDB]
ORM / Query:      [Ví dụ: SQLAlchemy 2.0 & Alembic / Prisma / Drizzle / Raw SQL]
Data Isolation:   [Ví dụ: Multi-tenant tenant_id isolation / Single tenant]
```

### Testing Framework
```
Test Runner:      [Ví dụ: Pytest / Vitest / Jest / Go test]
Types of Tests:   [Unit Tests, Integration Tests, End-to-End Tests]
```

---

## 2. Cấu trúc Thư mục Dự án (Directory Structure)

```
[project-root]/
├── src/ (hoặc app/)
│   ├── main.py (hoặc index.ts)       # Application entry point
│   ├── config/                       # Application configuration
│   ├── api/                          # Routers / Handlers / Controllers
│   ├── services/                     # Business Logic Layer
│   ├── db/                           # Models, Database session & Migrations
│   ├── middlewares/                  # Application Middlewares
│   └── schemas/                      # DTOs / Schemas for validation
├── tests/                            # Test Suite
├── .env.example                      # Template environment variables
├── pyproject.toml / package.json     # Dependency manifest
└── README.md                         # Project documentation
```

---

## 3. Database Schema & Data Models

```
[Mô tả các data models / entities của hệ thống]

Ví dụ:
- User (id, email, password_hash, created_at)
- Post (id, user_id, title, content, created_at)
```

---

## 4. API Contracts & Specifications

### Endpoint Overview
- **`POST /api/v1/[endpoint]`**: [Mô tả endpoint]
  - **Headers Required**: `[Header-Name]: [Type]`
  - **Request Body**:
    ```json
    {
      "[field_name]": "[type]"
    }
    ```
  - **Response 200 OK**:
    ```json
    {
      "status": "success",
      "data": {}
    }
    ```
  - **Response Error (4xx / 5xx)**:
    ```json
    {
      "error": "[ERROR_CODE]",
      "message": "[Error description]"
    }
    ```

---

## 5. Environment Variables Template (`.env.example`)

```bash
# Server Configuration
PORT=3000
ENVIRONMENT=development

# Database Connection
DATABASE_URL="postgresql://user:password@localhost:5432/dbname"

# External API Keys / Secrets
API_KEY=your_api_key_here
```

---

## 6. Build, Run & Verification Commands

```bash
# Cài đặt dependencies
[Command cài đặt, e.g. pip install -r requirements.txt hoac npm install]

# Khởi chạy development server
[Command khởi chạy, e.g. uvicorn app.main:app --reload hoac npm run dev]

# Chạy test suite
[Command chạy tests, e.g. pytest hoac npm test]
```
