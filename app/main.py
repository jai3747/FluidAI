import os
import time
import redis
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="FluidAI Demo API", version="1.0.0")

# Redis connection — read from env vars
REDIS_HOST = os.getenv("REDIS_HOST", "redis-service")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")

redis_client = None


def get_redis():
    global redis_client
    if redis_client is None:
        redis_client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            password=REDIS_PASSWORD if REDIS_PASSWORD else None,
            decode_responses=True,
            socket_connect_timeout=5,
        )
    return redis_client


@app.get("/")
def root():
    return {"message": "FluidAI Demo API is running", "version": "1.0.0"}


@app.get("/health")
def health():
    """Liveness probe — just confirms the process is alive."""
    return {"status": "alive", "timestamp": time.time()}


@app.get("/ready")
def ready():
    """Readiness probe — confirms Redis is reachable before accepting traffic."""
    try:
        r = get_redis()
        r.ping()
        return {"status": "ready", "redis": "connected"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=f"Redis not reachable: {str(e)}")


@app.get("/counter")
def get_counter():
    """Increment and return a visit counter stored in Redis."""
    try:
        r = get_redis()
        count = r.incr("visit_count")
        return {"visit_count": count, "redis_host": REDIS_HOST}
    except Exception as e:
        logger.error(f"Counter error: {e}")
        raise HTTPException(status_code=500, detail=f"Redis error: {str(e)}")


@app.get("/set/{key}/{value}")
def set_key(key: str, value: str):
    """Set a key in Redis."""
    try:
        r = get_redis()
        r.set(key, value)
        return {"set": key, "value": value}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/get/{key}")
def get_key(key: str):
    """Get a key from Redis."""
    try:
        r = get_redis()
        value = r.get(key)
        if value is None:
            raise HTTPException(status_code=404, detail=f"Key '{key}' not found")
        return {"key": key, "value": value}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
