# ── Stage 1: build deps ──────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Install deps into a separate dir so we can copy cleanly
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: minimal runtime image ───────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

# Non-root user for security — create BEFORE copy so --chown works
RUN adduser --disabled-password --gecos "" appuser

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy app source (owned by appuser, not root)
COPY --chown=appuser:appuser main.py .

USER appuser

EXPOSE 8000

# Uvicorn — single worker is fine for this demo
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
