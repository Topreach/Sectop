"""
FastAPI ML Service for Danger Emergence System.

Provides:
- Message prioritization using BART-based model
- Distress classification
- Batch processing for offline sync
- Health monitoring endpoints
"""

import os
import time
import logging
from typing import List, Optional
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

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
    """Load model on startup and clean up on shutdown."""
    global model, tokenizer, model_loaded
    logger.info("Starting ML Service...")
    
    # Try to load the model
    try:
        _load_model()
        model_loaded = True
        logger.info("Model loaded successfully")
    except Exception as e:
        logger.warning(f"Model not available, using rule-based fallback: {e}")
        model_loaded = False
    
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
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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
    """Rule-based fallback prioritization when model is not available."""
    text_lower = text.lower()
    score = 0
    
    # Critical keywords
    critical_keywords = [
        "help", "sos", "emergency", "fire", "trapped", "bleeding",
        "heart attack", "stroke", "gunshot", "collapse", "unconscious",
        "not breathing", "severe", "critical", "dying",
    ]
    
    # High priority keywords
    high_keywords = [
        "injured", "accident", "danger", "flood", "earthquake",
        "hurt", "pain", "broken", "burn", "smoke",
    ]
    
    # Medium priority keywords
    medium_keywords = [
        "need", "require", "assist", "unsafe",
        "warning", "caution", "alert",
    ]
    
    for kw in critical_keywords:
        if kw in text_lower:
            score += 3
    
    for kw in high_keywords:
        if kw in text_lower:
            score += 2
    
    for kw in medium_keywords:
        if kw in text_lower:
            score += 1
    
    if "urgent" in text_lower or "immediately" in text_lower:
        score += 2
    if "please" in text_lower or "asap" in text_lower:
        score += 1
    
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
):
    """
    Analyze a message and return its priority level.
    
    Uses the BART-based model if available, falls back to rule-based analysis.
    """
    global total_inferences
    
    start = time.time()
    
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
async def prioritize_batch(request: BatchPrioritizeRequest):
    """
    Batch prioritize multiple messages.
    """
    global total_inferences
    
    start = time.time()
    results = []
    
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
