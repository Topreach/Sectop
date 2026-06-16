"""
FastAPI ML Service for Danger Emergence System.

Provides:
- Message prioritization using BART-based model
- Distress classification
- Batch processing for offline sync
- Health monitoring endpoints
- Predictive ML model (Prophet + XGBoost) for terrorist activity forecasting
- Training pipeline for spatio-temporal risk scoring
"""

import os
import time
import logging
from typing import List, Optional
from datetime import datetime, timezone
import jwt
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, HTTPException, BackgroundTasks, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# Import predictive ML modules
from .models.schemas import (
    ForecastRequest, ForecastResponse,
    BatchForecastRequest, BatchForecastResponse,
    HotspotQuery, HotspotResponse,
    TrainRequest, TrainResponse,
    TrainingStatus, ModelInfo,
    HealthResponse as PredictiveHealthResponse,
)
from .inference.predictor import forecast_area, detect_hotspots
from .inference.batch_predictor import batch_forecast, forecast_all_nigerian_states
from .training.pipeline import run_training_pipeline, run_training_async, get_training_status
from .training.prophet_trainer import get_training_metrics as get_prophet_metrics
from .training.xgboost_trainer import get_training_metrics as get_xgboost_metrics, get_feature_names

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Global model reference
model = None
tokenizer = None
model_loaded = False

# Priority labels
PRIORITY_LABELS = [
    "LOW - General information",
    "MEDIUM - Caution advisory",
    "HIGH - Urgent assistance needed",
    "CRITICAL - Life-threatening emergency",
]


class PrioritizeRequest(BaseModel):
    """Request model for message prioritization."""
    text: str = Field(..., min_length=1, max_length=1000, description="Message text to analyze")
    context: Optional[dict] = Field(None, description="Additional context (location, user role, etc.)")


class PrioritizeResponse(BaseModel):
    """Response model for prioritization result."""
    priority: int = Field(..., ge=0, le=3, description="Priority level (0-3)")
    label: str = Field(..., description="Human-readable priority label")
    confidence: float = Field(..., ge=0.0, le=1.0, description="Model confidence score")
    inference_time_ms: float = Field(..., description="Inference time in milliseconds")
    method: str = Field(..., description="Method used (model or rule-based)")


class BatchPrioritizeRequest(BaseModel):
    """Request model for batch prioritization."""
    messages: List[str] = Field(..., min_length=1, max_length=100, description="List of messages to analyze")


class BatchPrioritizeResponse(BaseModel):
    """Response model for batch prioritization."""
    results: List[PrioritizeResponse]
    total_time_ms: float


class HealthResponse(BaseModel):
    """Response model for health check."""
    status: str
    model_loaded: bool
    uptime_seconds: float
    total_inferences: int


# Inference tracking
start_time = time.time()
total_inferences = 0


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load models on startup and clean up on shutdown."""
    global model, tokenizer, model_loaded
    logger.info("Starting ML Service...")
    
    # Try to load the BART prioritization model
    try:
        _load_model()
        model_loaded = True
        logger.info("BART model loaded successfully")
    except Exception as e:
        logger.warning(f"BART model not available, using rule-based fallback: {e}")
        model_loaded = False
    
    # Check predictive model status
    try:
        from .training.xgboost_trainer import get_training_metrics
        xgb_metrics = get_training_metrics()
        if xgb_metrics.get("status") == "trained":
            logger.info(f"XGBoost model available: version={xgb_metrics.get('model_version')}, "
                         f"R2={xgb_metrics.get('r2_score', 'N/A')}")
        else:
            logger.info("XGBoost model not yet trained. Use POST /api/v1/predictive/train to train.")
    except Exception as e:
        logger.warning(f"Could not check predictive model status: {e}")
    
    yield
    
    # Cleanup
    global model, tokenizer
    model = None
    tokenizer = None
    logger.info("ML Service shutdown complete")


app = FastAPI(
    title="Danger Emergence ML Service",
    description="AI-powered message prioritization and distress detection",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS configuration
allowed_origins = os.getenv("ML_ALLOWED_ORIGINS")
if allowed_origins:
    origins = [o.strip() for o in allowed_origins.split(",") if o.strip()]
else:
    origins = ["https://app.dangeremergence.com"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)

# Simple API key auth for service-to-service calls
ML_API_KEY = os.getenv("ML_API_KEY")
ML_SERVICE_JWT_SECRET = os.getenv("ML_SERVICE_JWT_SECRET")

def verify_service_jwt(token: Optional[str]):
    if ML_SERVICE_JWT_SECRET is None:
        # If not configured, disallow JWT auth
        return False
    if not token:
        return False
    try:
        # Decode without verifying algorithms list to be flexible but verify signature
        payload = jwt.decode(token, ML_SERVICE_JWT_SECRET, algorithms=["HS256"])
        # Optionally check issuer/audience
        return True
    except Exception:
        return False

def require_ml_api_key(api_key: Optional[str], bearer_jwt: Optional[str] = None):
    # If no ML_API_KEY is configured, allow all internal requests (Docker network)
    if not ML_API_KEY:
        return
    # Allow either a configured API key or a valid service JWT
    if api_key and api_key == ML_API_KEY:
        return
    if bearer_jwt and bearer_jwt.startswith("Bearer "):
        token = bearer_jwt.split(" ", 1)[1]
        if verify_service_jwt(token):
            return
    raise HTTPException(status_code=401, detail="Unauthorized: invalid ML service credentials")


def _load_model():
    """Load the BART-based emergency classification model."""
    global model, tokenizer
    
    model_name = os.getenv("MODEL_NAME", "facebook/bart-large-mnli")
    
    from transformers import AutoTokenizer, AutoModelForSequenceClassification
    
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForSequenceClassification.from_pretrained(
        model_name,
        num_labels=4,
        ignore_mismatched_sizes=True,
    )
    model.eval()


def _rule_based_prioritize(text: str) -> tuple:
    """Rule-based fallback prioritization when model is not available.
    
    Includes Nigerian language keywords (Hausa/Fulani, Yoruba, Igbo)
    for regional threat detection context.
    """
    text_lower = text.lower()
    score = 0
    
    # Critical keywords (English)
    critical_keywords = [
        "help", "sos", "emergency", "fire", "trapped", "bleeding",
        "heart attack", "stroke", "gunshot", "collapse", "unconscious",
        "not breathing", "severe", "critical", "dying",
    ]
    
    # High priority keywords (English)
    high_keywords = [
        "injured", "accident", "danger", "flood", "earthquake",
        "hurt", "pain", "broken", "burn", "smoke",
    ]
    
    # Medium priority keywords (English)
    medium_keywords = [
        "need", "require", "assist", "unsafe",
        "warning", "caution", "alert",
    ]
    
    # --- Nigerian Language Keywords ---
    # Hausa/Fulani critical threat keywords
    hausa_critical = [
        "garkuwa",     # kidnapping
        "bindiga",     # gun
        "ta'addanci",  # terrorism
        "harbi",       # shoot
        "kashe",       # kill
        "bom",         # bomb
        "fijo",        # attack (Fulfulde)
        "'yan fashi",  # bandits
        "'yan ta'adda",# terrorists
        "maharbi",     # shooter
    ]
    
    # Hausa/Fulani high priority keywords
    hausa_high = [
        "yaki",        # war
        "fashi",       # robbery
        "wuta",        # fire
        "makami",      # weapon
        "mahaukata",   # mad ones
        "suna zuwa",   # they are coming
        "fulani",      # fulani mention
        "nyifta",      # hide (Fulfulde)
        "war",         # war (Fulfulde)
    ]
    
    # Hausa medium priority keywords
    hausa_medium = [
        "taimako",     # help
        "a gudu",      # run away
        "dare",        # night
        "doki",        # horse
        "ballal",      # help (Fulfulde)
        "nyaw",        # sickness (Fulfulde)
    ]
    
    # Yoruba keywords
    yoruba_critical = [
        "gbigbe",      # kidnapping
        "ibon",        # gun
        "ikọlu",       # attack
        "apaniyan",    # murder
    ]
    
    yoruba_high = [
        "panumopa",    # emergency
        "ina",         # fire
        "ologun",      # warrior
        "ipalara",     # injury
    ]
    
    yoruba_medium = [
        "iranlowo",    # help
        "sare",        # run
    ]
    
    # Igbo keywords
    igbo_critical = [
        "atogboro",    # kidnapping
        "nkwatogbo",   # terrorism
        "egbe",        # gun
        "igbu",        # kill
        "nwakpọrọ",    # kidnapper
    ]
    
    igbo_high = [
        "ogu",         # war
        "oku",         # fire
        "ndi ọjọọ",   # evil ones
    ]
    
    igbo_medium = [
        "enyemaka",    # help
        "oso",         # run
    ]
    
    # Score English keywords
    for kw in critical_keywords:
        if kw in text_lower:
            score += 3
    
    for kw in high_keywords:
        if kw in text_lower:
            score += 2
    
    for kw in medium_keywords:
        if kw in text_lower:
            score += 1
    
    # Score Hausa/Fulani keywords
    for kw in hausa_critical:
        if kw in text_lower:
            score += 3
    
    for kw in hausa_high:
        if kw in text_lower:
            score += 2
    
    for kw in hausa_medium:
        if kw in text_lower:
            score += 1
    
    # Score Yoruba keywords
    for kw in yoruba_critical:
        if kw in text_lower:
            score += 3
    
    for kw in yoruba_high:
        if kw in text_lower:
            score += 2
    
    for kw in yoruba_medium:
        if kw in text_lower:
            score += 1
    
    # Score Igbo keywords
    for kw in igbo_critical:
        if kw in text_lower:
            score += 3
    
    for kw in igbo_high:
        if kw in text_lower:
            score += 2
    
    for kw in igbo_medium:
        if kw in text_lower:
            score += 1
    
    # Urgency modifiers
    if "urgent" in text_lower or "immediately" in text_lower:
        score += 2
    if "please" in text_lower or "asap" in text_lower:
        score += 1
    
    # Exclamation marks
    exclamation_count = text.count("!")
    if exclamation_count >= 3:
        score += 1
    if exclamation_count >= 5:
        score += 1
    
    if score >= 6:
        return 3, min(1.0, score / 8.0)
    elif score >= 4:
        return 2, min(1.0, score / 6.0)
    elif score >= 2:
        return 1, min(1.0, score / 4.0)
    else:
        return 0, 0.5


def _model_prioritize(text: str) -> tuple:
    """Prioritize message using the loaded model."""
    global model, tokenizer
    
    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        max_length=128,
        padding=True,
    )
    
    import torch
    with torch.no_grad():
        outputs = model(**inputs)
        probabilities = torch.nn.functional.softmax(outputs.logits, dim=-1)
        priority = torch.argmax(probabilities, dim=1).item()
        confidence = probabilities[0][priority].item()
    
    return priority, confidence


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        status="healthy",
        model_loaded=model_loaded,
        uptime_seconds=time.time() - start_time,
        total_inferences=total_inferences,
    )


@app.post("/api/v1/prioritize", response_model=PrioritizeResponse)
async def prioritize_message(
    request: PrioritizeRequest,
    background_tasks: BackgroundTasks,
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Analyze a message and return its priority level.
    
    Uses the BART-based model if available, falls back to rule-based analysis.
    """
    global total_inferences
    
    start = time.time()
    
    # Validate API key (from Authorization: ApiKey <key> or X-API-KEY)
    api_key = None
    if authorization:
        # support 'ApiKey <key>' or 'Bearer <key>' forms
        parts = authorization.split()
        if len(parts) == 2:
            api_key = parts[1]

    require_ml_api_key(api_key, authorization)

    if model_loaded and model is not None:
        priority, confidence = _model_prioritize(request.text)
        method = "model"
    else:
        priority, confidence = _rule_based_prioritize(request.text)
        method = "rule-based"
    
    inference_time = (time.time() - start) * 1000
    total_inferences += 1
    
    # Log for training data collection
    background_tasks.add_task(
        _log_for_training, request.text, priority, confidence, method
    )
    
    return PrioritizeResponse(
        priority=priority,
        label=PRIORITY_LABELS[priority],
        confidence=confidence,
        inference_time_ms=inference_time,
        method=method,
    )


@app.post("/api/v1/prioritize/batch", response_model=BatchPrioritizeResponse)
async def prioritize_batch(request: BatchPrioritizeRequest, authorization: Optional[str] = Header(None, alias="Authorization")):
    """
    Batch prioritize multiple messages.
    """
    global total_inferences
    
    start = time.time()
    results = []
    
    # Validate API key
    api_key = None
    if authorization:
        parts = authorization.split()
        if len(parts) == 2:
            api_key = parts[1]
    require_ml_api_key(api_key, authorization)

    for message in request.messages:
        msg_start = time.time()
        
        if model_loaded and model is not None:
            priority, confidence = _model_prioritize(message)
            method = "model"
        else:
            priority, confidence = _rule_based_prioritize(message)
            method = "rule-based"
        
        inference_time = (time.time() - msg_start) * 1000
        total_inferences += 1
        
        results.append(PrioritizeResponse(
            priority=priority,
            label=PRIORITY_LABELS[priority],
            confidence=confidence,
            inference_time_ms=inference_time,
            method=method,
        ))
    
    total_time = (time.time() - start) * 1000
    
    return BatchPrioritizeResponse(
        results=results,
        total_time_ms=total_time,
    )


@app.get("/api/v1/metrics")
async def get_metrics():
    """Get service metrics."""
    return {
        "total_inferences": total_inferences,
        "model_loaded": model_loaded,
        "uptime_seconds": time.time() - start_time,
        "inferences_per_second": total_inferences / (time.time() - start_time) if (time.time() - start_time) > 0 else 0,
    }


# ═══════════════════════════════════════════════════════════════
#  Predictive ML Model Endpoints (Prophet + XGBoost)
# ═══════════════════════════════════════════════════════════════

@app.get("/api/v1/predictive/health", response_model=PredictiveHealthResponse)
async def predictive_health():
    """Health check for the predictive ML model."""
    training_status = get_training_status()
    xgb_metrics = get_xgboost_metrics()
    prophet_metrics = get_prophet_metrics()

    return PredictiveHealthResponse(
        status="healthy",
        model_loaded=xgb_metrics.get("status") == "trained",
        uptime_seconds=time.time() - start_time,
        total_predictions=total_inferences,
        model_version=xgb_metrics.get("model_version", "untrained"),
    )


@app.post("/api/v1/predictive/forecast", response_model=ForecastResponse)
async def get_forecast(
    request: ForecastRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Generate a terrorist activity forecast for a specific area.

    Uses the Prophet + XGBoost hybrid model to predict incident counts
    and risk scores across grid cells in the requested area.

    Supports:
    - Location-based: Provide latitude + longitude + radius_km
    - State-level: Provide state name
    - LGA-level: Provide state + lga
    """
    api_key = _extract_api_key(authorization)
    require_ml_api_key(api_key, authorization)

    lat = request.latitude
    lng = request.longitude

    # If state provided, use state capital coordinates
    if request.state and (lat is None or lng is None):
        state_coords = _get_state_coordinates(request.state)
        if state_coords:
            lat, lng = state_coords

    # Default to Abuja if nothing specified
    if lat is None:
        lat = 9.0667
    if lng is None:
        lng = 7.4833

    result = forecast_area(
        latitude=lat,
        longitude=lng,
        radius_km=request.radius_km or 50.0,
        forecast_hours=request.forecast_hours,
        min_risk_threshold=request.min_risk_threshold,
        include_hotspots=request.include_hotspots,
    )

    return result


@app.post("/api/v1/predictive/forecast/batch", response_model=BatchForecastResponse)
async def get_batch_forecast(
    request: BatchForecastRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Generate forecasts for multiple areas in a single request.

    Useful for dashboard overviews and state-level monitoring.
    """
    api_key = _extract_api_key(authorization)
    require_ml_api_key(api_key, authorization)

    result = batch_forecast(request.areas)
    return result


@app.post("/api/v1/predictive/hotspots", response_model=HotspotResponse)
async def get_hotspots(
    request: HotspotQuery,
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Detect high-risk hotspots within a radius of a location.

    Returns cells with risk scores above the threshold, sorted by risk.
    """
    api_key = _extract_api_key(authorization)
    require_ml_api_key(api_key, authorization)

    result = detect_hotspots(
        latitude=request.latitude,
        longitude=request.longitude,
        radius_km=request.radius_km,
        min_risk_threshold=request.min_risk_threshold,
    )

    return result


@app.post("/api/v1/predictive/train", response_model=TrainResponse)
async def train_models(
    request: TrainRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Trigger model training for the predictive ML pipeline.

    Trains Prophet models per grid cell and XGBoost risk scoring model.
    Training runs asynchronously in the background.
    """
    api_key = _extract_api_key(authorization)
    require_ml_api_key(api_key, authorization)

    # Check if training is already running
    status = get_training_status()
    if status["status"] == "running":
        return TrainResponse(
            status="rejected",
            message="Training is already in progress",
        )

    # Start training in background
    config = request.config
    run_training_async(
        history_days=config.history_days if config else 90,
        cell_size_deg=config.grid_cell_size_deg if config else 0.1,
        min_incidents_per_cell=config.min_incidents_per_cell if config else 3,
        prophet_seasonality_mode=config.prophet_seasonality_mode if config else "multiplicative",
        xgboost_n_estimators=config.xgboost_n_estimators if config else 200,
        xgboost_max_depth=config.xgboost_max_depth if config else 6,
        xgboost_learning_rate=config.xgboost_learning_rate if config else 0.05,
        test_split_ratio=config.test_split_ratio if config else 0.2,
        force_retrain=request.force_retrain,
    )

    return TrainResponse(
        status="accepted",
        message="Training started in background. Check /api/v1/predictive/training-status for progress.",
    )


@app.get("/api/v1/predictive/training-status", response_model=TrainingStatus)
async def get_training_status_endpoint():
    """Get the current training status."""
    return get_training_status()


@app.get("/api/v1/predictive/model-info", response_model=ModelInfo)
async def get_model_info():
    """Get information about the current predictive model state."""
    xgb_metrics = get_xgboost_metrics()
    prophet_metrics = get_prophet_metrics()
    training_status = get_training_status()
    feature_names = get_feature_names()

    return ModelInfo(
        model_version=xgb_metrics.get("model_version", "untrained"),
        last_trained=xgb_metrics.get("trained_at", None),
        total_cells_trained=prophet_metrics.get("total_cells_trained", 0),
        prophet_models_available=prophet_metrics.get("total_cells_trained", 0) > 0,
        xgboost_model_available=xgb_metrics.get("status") == "trained",
        training_status=TrainingStatus(**training_status),
        feature_count=len(feature_names) if feature_names else 30,
    )


@app.post("/api/v1/predictive/forecast/all-states")
async def forecast_all_states(
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Generate forecasts for all 36 Nigerian states + FCT.

    Returns a map of state name -> forecast summary.
    """
    api_key = _extract_api_key(authorization)
    require_ml_api_key(api_key, authorization)

    results = forecast_all_nigerian_states()

    state_forecasts = {}
    for i, (state_name, _, _) in enumerate(_NIGERIAN_STATE_CAPITALS):
        if i < len(results):
            r = results[i]
            state_forecasts[state_name] = {
                "overall_risk_score": r.overall_risk_score,
                "overall_alert_level": r.overall_alert_level,
                "hotspot_count": len(r.hotspots),
                "total_cells_analyzed": r.total_cells_analyzed,
            }

    return {
        "forecasts": state_forecasts,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_states": len(state_forecasts),
    }


# ═══════════════════════════════════════════════════════════════
#  Helper Functions
# ═══════════════════════════════════════════════════════════════

def _extract_api_key(authorization: Optional[str]) -> Optional[str]:
    """Extract API key from Authorization header."""
    if not authorization:
        return None
    parts = authorization.split()
    if len(parts) == 2:
        return parts[1]
    return None


# Nigerian state capitals for coordinate lookup
_NIGERIAN_STATE_CAPITALS = [
    ("Abia", 5.5333, 7.4833),
    ("Adamawa", 9.3333, 12.5000),
    ("Akwa Ibom", 5.0333, 7.9167),
    ("Anambra", 6.3333, 6.8333),
    ("Bauchi", 11.8333, 9.8333),
    ("Bayelsa", 4.9167, 6.0833),
    ("Benue", 7.3333, 8.7500),
    ("Borno", 11.8333, 13.1500),
    ("Cross River", 4.9500, 8.3167),
    ("Delta", 6.3333, 5.6167),
    ("Ebonyi", 6.3167, 8.1000),
    ("Edo", 6.3167, 5.6000),
    ("Ekiti", 7.6667, 5.3167),
    ("Enugu", 6.4333, 7.4833),
    ("FCT", 9.0667, 7.4833),
    ("Gombe", 10.2833, 10.7500),
    ("Imo", 5.4833, 7.0333),
    ("Jigawa", 11.8000, 9.3500),
    ("Kaduna", 10.5167, 7.4333),
    ("Kano", 12.0000, 8.5167),
    ("Katsina", 12.9833, 7.6000),
    ("Kebbi", 12.4500, 4.2000),
    ("Kogi", 7.8000, 6.7333),
    ("Kwara", 8.5000, 4.5500),
    ("Lagos", 6.4500, 3.4000),
    ("Nasarawa", 8.5333, 7.7000),
    ("Niger", 9.5833, 6.5500),
    ("Ogun", 7.1500, 3.3500),
    ("Ondo", 7.2500, 5.2000),
    ("Osun", 7.7667, 4.5667),
    ("Oyo", 7.8333, 3.9333),
    ("Plateau", 9.9333, 8.8833),
    ("Rivers", 4.8167, 7.0167),
    ("Sokoto", 13.0667, 5.2333),
    ("Taraba", 7.8833, 9.8500),
    ("Yobe", 11.7500, 11.6667),
    ("Zamfara", 12.1667, 6.6667),
]


def _get_state_coordinates(state_name: str) -> Optional[tuple]:
    """Get coordinates for a Nigerian state capital."""
    state_lower = state_name.lower().replace(" ", "")
    for name, lat, lng in _NIGERIAN_STATE_CAPITALS:
        if name.lower().replace(" ", "") == state_lower:
            return (lat, lng)
    return None


async def _log_for_training(text: str, priority: int, confidence: float, method: str):
    """Log inference data for future model training."""
    logger.info(
        f"Inference: priority={priority}, confidence={confidence:.3f}, "
        f"method={method}, text_preview={text[:50]}..."
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
    )
