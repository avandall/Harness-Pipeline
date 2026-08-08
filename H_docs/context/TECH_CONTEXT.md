# TECH CONTEXT
# Bối cảnh kỹ thuật — Stack, môi trường và kiến trúc cụ thể (Python Stack)

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** 2026-08-07 (Refactored to 100% Python Stack per User Rule)

---

## 1. Tech Stack ($0 Stack Promise - Pure Python)

### Language & Framework
```
Runtime:          Python 3.11+
Framework:        FastAPI
Web Server:       Uvicorn (ASGI Server)
Data Validation:  Pydantic v2
API Protocol:     REST API (JSON)
Tenant Context:   Header-based `X-Tenant-ID`
```

### Database & ORM
```
Primary Database: PostgreSQL 15 (Docker Container)
ORM / Query:      SQLAlchemy 2.0 (AsyncSession) & Alembic (Migrations)
Data Isolation:   Multi-tenant schema cách ly theo tenant_id
```

### Stripe Integration & Local Tooling
```
Stripe API Mode:  Stripe Test Mode (sk_test_..., whsec_...)
SDK:              Stripe Python SDK (`stripe`)
CLI Tool:         Stripe CLI (`stripe listen --forward-to localhost:3000/webhooks/stripe`, `stripe trigger`)
Test Card:        4242 4242 4242 4242 (với ngày hết hạn bất kỳ trong tương lai)
```

### Testing Framework
```
Test Runner:      Pytest (`pytest`, `pytest-asyncio`, `httpx`)
Types of Tests:   Unit Tests (Money Math), Integration Tests (Idempotency, Boundary Quotas), Webhook Verification Tests
```

---

## 2. Cấu trúc Thư mục Dự án (Python Directory Structure)

```
flyrank-capstone-metering-billing/
├── app/
│   ├── main.py                       # FastAPI application entry point
│   ├── config/                       # Pricing constants & plan limits
│   │   ├── chat_pricing_config.py    # AI token pricing table & integer math helpers
│   │   └── plans_config.py           # Free & Pro quota thresholds
│   ├── api/                          # FastAPI Routers / Endpoints
│   │   ├── generate.py               # Billable endpoint handler (POST /generate)
│   │   ├── usage.py                  # Rollup endpoint handler (GET /usage)
│   │   └── webhooks.py               # Stripe webhook handler (POST /webhooks/stripe)
│   ├── services/                     # Core Business Logic (Domain Layer)
│   │   ├── meter_service.py          # Record usage, Idempotency key deduplication
│   │   ├── quota_service.py          # Boundary quota checks, status codes 429/402
│   │   ├── cost_service.py           # Token pricing calculation (cached, reasoning, output)
│   │   └── stripe_service.py         # Signature verification, webhook deduplication & plan flip
│   ├── db/                           # SQLAlchemy Database Models & Alembic migrations
│   │   ├── base.py                   # SQLAlchemy Base metadata & engine configuration
│   │   ├── models.py                 # DB Schema models (Tenant, Plan, Subscription, UsageEvent, etc.)
│   │   ├── migrations/               # Alembic migrations directory
│   │   └── seed.py                   # Seed script for Free/Pro tenants & plans
│   ├── middlewares/                  # FastAPI Middlewares / Dependencies
│   │   ├── idempotency.py            # Parse X-Tenant-ID & Idempotency-Key
│   │   └── error_handler.py          # Global error formatting (429, 402, 400, 500)
│   └── schemas/                      # Pydantic schemas (Request/Response validation)
├── tests/                            # Pytest Test Suite
│   ├── test_pricing.py               # Pinned pricing math unit tests (PROBE 5)
│   ├── test_idempotency.py           # Duplicate request prevention tests (PROBE 1)
│   ├── test_boundary_quota.py        # Quota limit & 429/402 status tests (PROBE 2)
│   └── test_webhook.py               # Forged signature & replay webhook tests (PROBE 3 & 4)
├── alembic.ini                       # Alembic database migration config
├── capstone.yaml                     # Evaluator manifest file (run, seed, test, base_url)
├── EVIDENCE.md                       # Proof of solution per DoD checkbox
├── BUILDLOG.md                       # AI assistance log & engineering notes
├── README.md                         # Architecture diagram, setup & run instructions
├── .env.example                      # Template environment variables
├── pyproject.toml                    # Standard Python package & dependency manifest (MANDATORY)
├── requirements.txt                  # Python dependencies
└── docker-compose.yml                # Docker compose for PostgreSQL 15
```

---

## 3. Detailed Database Schema (SQLAlchemy 2.0 Models)

```python
import uuid
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, UniqueConstraint, JSON, func
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

class Tenant(Base):
    __tablename__ = "tenants"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    stripe_customer_id = Column(String, unique=True, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Plan(Base):
    __tablename__ = "plans"
    id = Column(String, primary_key=True) # "free", "pro"
    name = Column(String, nullable=False)
    max_api_calls_per_month = Column(Integer, nullable=False)
    max_tokens_per_month = Column(Integer, nullable=False)

class Subscription(Base):
    __tablename__ = "subscriptions"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False)
    plan_id = Column(String, ForeignKey("plans.id"), nullable=False)
    stripe_sub_id = Column(String, unique=True, nullable=True)
    status = Column(String, nullable=False) # "active", "past_due", "canceled"
    current_period_start = Column(DateTime(timezone=True), nullable=False)
    current_period_end = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class UsageEvent(Base):
    __tablename__ = "usage_events"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False)
    event_type = Column(String, nullable=False) # "api_call", "ai_generation"
    api_calls_count = Column(Integer, default=1)
    input_tokens = Column(Integer, default=0)
    cached_input_tokens = Column(Integer, default=0)
    output_tokens = Column(Integer, default=0)
    reasoning_tokens = Column(Integer, default=0)
    calculated_cost_cents = Column(Integer, nullable=False) # Stored as Integer Cents!
    idempotency_key = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("tenant_id", "idempotency_key", name="uix_tenant_idempotency"),
    )

class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False)
    idempotency_key = Column(String, nullable=False)
    response_status = Column(Integer, nullable=False)
    response_body = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("tenant_id", "idempotency_key", name="uix_tenant_idempotency_record"),
    )

class ProcessedWebhook(Base):
    __tablename__ = "processed_webhooks"
    id = Column(String, primary_key=True) # Stripe event_id (evt_...)
    event_type = Column(String, nullable=False)
    processed_at = Column(DateTime(timezone=True), server_default=func.now())
```

---

## 4. Specification APIs (FastAPI Endpoints)

### A. Billable Endpoint: `POST /generate`
- **Headers Required**:
  - `X-Tenant-ID`: string (e.g. `tenant_free_01`)
  - `Idempotency-Key`: string (e.g. `req_abc123`)
- **Request Payload (Pydantic Schema)**:
  ```json
  {
    "prompt": "Explain quantum computing",
    "simulated_usage": {
      "input_tokens": 1500,
      "cached_input_tokens": 500,
      "output_tokens": 800,
      "reasoning_tokens": 200
    }
  }
  ```
- **Responses**:
  - **HTTP 200 OK**: Request allowed & usage recorded.
    ```json
    {
      "status": "success",
      "data": {
        "response": "Simulated output...",
        "usage_recorded": {
          "input_tokens": 1500,
          "cached_input_tokens": 500,
          "output_tokens": 800,
          "reasoning_tokens": 200,
          "total_tokens": 3000,
          "cost_cents": 3
        }
      }
    }
    ```
  - **HTTP 429 Too Many Requests** (Quota Exceeded):
    ```json
    {
      "error": "QUOTA_EXCEEDED",
      "message": "Monthly AI token quota exceeded for Free plan (100,000 tokens limit). Please upgrade to Pro.",
      "quota_status": {
        "used": 100000,
        "limit": 100000,
        "requested": 3000
      }
    }
    ```
  - **HTTP 402 Payment Required** (Subscription Past Due / Needs Upgrade):
    ```json
    {
      "error": "PAYMENT_REQUIRED",
      "message": "Tenant subscription is past due or unpaid. Upgrade or clear invoice to continue.",
      "checkout_url": "/create-checkout-session?tenantId=tenant_free_01"
    }
    ```

### B. Usage Rollup Endpoint: `GET /usage`
- **Headers Required**: `X-Tenant-ID`: `tenant_free_01`
- **Query Params**: `?month=2026-08` (Default: current month)
- **Response HTTP 200 OK**:
  ```json
  {
    "tenant_id": "tenant_free_01",
    "plan": "Free",
    "period": "2026-08",
    "api_calls": {
      "used": 150,
      "limit": 1000
    },
    "ai_tokens": {
      "used": 45000,
      "limit": 100000,
      "breakdown": {
        "input_tokens": 25000,
        "cached_input_tokens": 10000,
        "output_tokens": 8000,
        "reasoning_tokens": 2000
      }
    },
    "cost": {
      "currency": "USD",
      "total_cents": 125,
      "formatted": "$1.25"
    }
  }
  ```

### C. Stripe Webhook Endpoint: `POST /webhooks/stripe`
- **Headers**: `stripe-signature`: `t=...,v1=...`
- **FastAPI Implementation Note**:
  Using `payload = await request.body()` to obtain exact raw bytes for `stripe.Webhook.construct_event(payload, sig_header, webhook_secret)`.
- **Behavior**:
  1. Verify signature with `STRIPE_WEBHOOK_SECRET` (`whsec_...`). If invalid -> Return **HTTP 400 Bad Request**.
  2. Check if `event.id` exists in `ProcessedWebhook`. If duplicate -> Return **HTTP 200 OK** `{"status": "already_processed"}`.
  3. Events:
     - `checkout.session.completed`: Upgrade Tenant Free -> Pro, set subscription active.
     - `customer.subscription.updated`: Sync subscription period & status.
     - `customer.subscription.deleted`: Revert Tenant Pro -> Free.

---

## 5. Token Pricing Rules & Money Math Engine (`chat_pricing_config.py`)

### Integer Money Math Rules (Python):
All monetary calculations use **Integer Micro-Cents** ($1 \text{ cent} = 10,000 \text{ micro-cents}$) to eliminate floating-point inaccuracies.

### Standard Pricing Table (per 1,000,000 tokens):
| Token Category | Rate per 1M Tokens | Micro-Cents per Token | Rule |
|----------------|---------------------|------------------------|------|
| `input_tokens` | $2.50 / 1M | 250 micro-cents | Standard input rate |
| `cached_input_tokens` | $1.25 / 1M | 125 micro-cents | Discounted cached rate (50% off) |
| `output_tokens` | $10.00 / 1M | 1,000 micro-cents | Standard output rate |
| `reasoning_tokens` | $10.00 / 1M | 1,000 micro-cents | **Billed at output_tokens rate** |

### Python Calculation Code:
```python
import math

INPUT_MICRO_CENTS_PER_TOKEN = 250
CACHED_INPUT_MICRO_CENTS_PER_TOKEN = 125
OUTPUT_MICRO_CENTS_PER_TOKEN = 1000
REASONING_MICRO_CENTS_PER_TOKEN = 1000

def calculate_token_cost_cents(
    input_tokens: int,
    cached_input_tokens: int,
    output_tokens: int,
    reasoning_tokens: int
) -> int:
    total_micro_cents = (
        (input_tokens * INPUT_MICRO_CENTS_PER_TOKEN) +
        (cached_input_tokens * CACHED_INPUT_MICRO_CENTS_PER_TOKEN) +
        (output_tokens * OUTPUT_MICRO_CENTS_PER_TOKEN) +
        (reasoning_tokens * REASONING_MICRO_CENTS_PER_TOKEN)
    )
    return math.ceil(total_micro_cents / 10_000)
```

---

## 6. Environment Variables Template (`.env.example`)

```bash
# Server Configuration
PORT=3000
ENVIRONMENT=development

# Database Connection (Docker PostgreSQL 15)
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5432/metering_dev"

# Stripe Test Mode Keys (NEVER COMMIT ACTUAL KEYS)
STRIPE_SECRET_KEY=sk_test_51...
STRIPE_WEBHOOK_SECRET=whsec_...

# Base Application URL
BASE_URL=http://localhost:3000
```

---

## 7. Submission Pack Manifest (`capstone.yaml`)

```yaml
version: "1.0"
capstone: flyrank-capstone-metering-billing
run: uvicorn app.main:app --host 0.0.0.0 --port 3000
seed: python -m app.db.seed
test: pytest
base_url: http://localhost:3000
probes:
  probe_1_idempotency: POST /generate
  probe_2_quota_boundary: POST /generate
  probe_3_stripe_checkout: POST /webhooks/stripe
  probe_4_webhook_forged_duplicate: POST /webhooks/stripe
  probe_5_pinned_pricing: GET /usage
```

---

## 8. Alignment with 5 Acceptance Probes (Pytest Suite)

| Probe | Test Case Description | Expected Result | Verification File |
|-------|-----------------------|-----------------|-------------------|
| **PROBE 1** | Send duplicate `POST /generate` requests with exact same `Idempotency-Key` | 1 usage event in DB; 2nd call returns identical response | `tests/test_idempotency.py` |
| **PROBE 2** | Call API up to exact quota limit (1,000 calls / 100k tokens), then call 1 more | Boundary call succeeds; next call returns HTTP `429` or `402` | `tests/test_boundary_quota.py` |
| **PROBE 3** | Complete Stripe test checkout -> Webhook fires `checkout.session.completed` | Tenant flips Free -> Pro; `GET /usage` shows Pro quota limits | `tests/test_webhook.py` |
| **PROBE 4** | Send forged webhook (bad signature) & send valid webhook twice | Forged returns HTTP `400`; duplicate valid webhook processed once | `tests/test_webhook.py` |
| **PROBE 5** | Execute pinned cost calculation tests with cached & reasoning tokens | Exact integer cost matches expected total; `GET /usage` matches | `tests/test_pricing.py` |

