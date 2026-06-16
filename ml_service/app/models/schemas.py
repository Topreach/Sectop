"""
Pydantic schemas for the predictive ML model (Prophet + XGBoost).
Provides request/response models for forecasting, training, and hotspot detection.
"""

from __future__ import annotations
from typing import List, Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field


# ──────────────────────────────────────────────
#  Training Schemas
# ──────────────────────────────────────────────

class TrainingConfig(BaseModel):
    """Configuration for model training."""
    history_days: int = Field(90, ge=7, le=365, description="Days of historical data to use")
    forecast_days: int = Field(7, ge=1, le=30, description="Days to forecast ahead")
    grid_cell_size_deg: float = Field(0.1, ge=0.01, le=1.0, description="Grid cell size in degrees (~11km at equator)")
    min_incidents_per_cell: int = Field(3, ge=1, description="Minimum incidents required to train a cell model")
    prophet_seasonality_mode: str = Field("multiplicative", pattern="^(additive|multiplicative)$")
    xgboost_n_estimators: int = Field(200, ge=50, le=1000)
    xgboost_max_depth: int = Field(6, ge=3, le=15)
    xgboost_learning_rate: float = Field(0.05, ge=0.001, le=1.0)
    test_split_ratio: float = Field(0.2, ge=0.1, le=0.4)


class TrainingStatus(BaseModel):
    """Status of a training run."""
    status: str = Field(..., pattern="^(idle|running|completed|failed)$")
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    total_cells: int = 0
    trained_cells: int = 0
    failed_cells: int = 0
    error_message: Optional[str] = None
    model_version: Optional[str] = None
    metrics: Optional[Dict[str, float]] = None


class TrainRequest(BaseModel):
    """Request to trigger model training."""
    config: Optional[TrainingConfig] = Field(default_factory=TrainingConfig)
    force_retrain: bool = Field(False, description="Force retrain even if model exists")


class TrainResponse(BaseModel):
    """Response from a training request."""
    status: str = Field(..., pattern="^(accepted|rejected)$")
    message: str
    training_id: Optional[str] = None


# ──────────────────────────────────────────────
#  Forecast Schemas
# ──────────────────────────────────────────────

class ForecastPoint(BaseModel):
    """A single forecast data point."""
    timestamp: str = Field(..., description="ISO 8601 timestamp")
    predicted_count: float = Field(..., ge=0.0, description="Predicted incident count")
    lower_bound: float = Field(..., ge=0.0, description="Lower confidence bound")
    upper_bound: float = Field(..., ge=0.0, description="Upper confidence bound")
    risk_score: float = Field(..., ge=0.0, le=1.0, description="Normalized risk score (0-1)")


class HotspotPrediction(BaseModel):
    """A predicted hotspot location."""
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    risk_score: float = Field(..., ge=0.0, le=1.0)
    alert_level: str = Field(..., pattern="^(Normal|Elevated|High|Severe|Critical)$")
    peak_time: Optional[str] = Field(None, description="Predicted peak time ISO 8601")
    expected_count_24h: float = Field(..., ge=0.0)
    trend_direction: str = Field(..., pattern="^(rising|falling|stable)$")
    contributing_factors: List[str] = Field(default_factory=list)
    state: Optional[str] = None
    lga: Optional[str] = None


class ForecastRequest(BaseModel):
    """Request for a forecast."""
    latitude: Optional[float] = Field(None, ge=-90, le=90, description="Center latitude for area forecast")
    longitude: Optional[float] = Field(None, ge=-180, le=180, description="Center longitude for area forecast")
    radius_km: Optional[float] = Field(None, ge=1.0, le=500.0, description="Radius in km for area forecast")
    state: Optional[str] = Field(None, description="Nigerian state for state-level forecast")
    lga: Optional[str] = Field(None, description="Local Government Area for LGA-level forecast")
    forecast_hours: int = Field(168, ge=1, le=720, description="Hours to forecast ahead (default 7 days)")
    include_hotspots: bool = Field(True, description="Include hotspot predictions")
    min_risk_threshold: float = Field(0.3, ge=0.0, le=1.0, description="Minimum risk score to include")


class ForecastResponse(BaseModel):
    """Response containing forecast data."""
    forecast_points: List[ForecastPoint] = Field(default_factory=list)
    hotspots: List[HotspotPrediction] = Field(default_factory=list)
    overall_risk_score: float = Field(..., ge=0.0, le=1.0)
    overall_alert_level: str = Field(..., pattern="^(Normal|Elevated|High|Severe|Critical)$")
    model_version: str
    generated_at: str = Field(..., description="ISO 8601 timestamp")
    forecast_hours: int
    total_cells_analyzed: int = 0


# ──────────────────────────────────────────────
#  Batch Forecast Schemas
# ──────────────────────────────────────────────

class BatchForecastRequest(BaseModel):
    """Request for batch forecasting across multiple areas."""
    areas: List[ForecastRequest] = Field(..., min_length=1, max_length=50)


class BatchForecastResponse(BaseModel):
    """Response for batch forecasting."""
    results: List[ForecastResponse]
    total_time_ms: float


# ──────────────────────────────────────────────
#  Hotspot Schemas
# ──────────────────────────────────────────────

class HotspotQuery(BaseModel):
    """Query parameters for hotspot detection."""
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    radius_km: float = Field(50.0, ge=1.0, le=500.0)
    min_risk_threshold: float = Field(0.4, ge=0.0, le=1.0)
    include_trends: bool = Field(True)


class HotspotResponse(BaseModel):
    """Response containing hotspot predictions."""
    hotspots: List[HotspotPrediction]
    total_hotspots: int
    generated_at: str
    model_version: str


# ──────────────────────────────────────────────
#  Model Info Schemas
# ──────────────────────────────────────────────

class ModelInfo(BaseModel):
    """Information about the current model state."""
    model_version: str
    last_trained: Optional[datetime] = None
    total_cells_trained: int
    prophet_models_available: bool
    xgboost_model_available: bool
    training_status: TrainingStatus
    feature_count: int = 30


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    model_loaded: bool
    uptime_seconds: float
    total_predictions: int
    model_version: str
