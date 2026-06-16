"""
Real-time prediction module for the Prophet + XGBoost hybrid model.
Generates forecasts and risk scores for specific locations/areas.

Supports:
- Single cell forecast (given lat/lng)
- Area forecast (given center + radius)
- State/LGA level forecast
- Hotspot detection (top risk cells)
"""

import os
import json
import logging
import math
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta, date, timezone

import numpy as np
import pandas as pd

from ..training import data_collector
from ..training import feature_engineer as fe
from ..training import prophet_trainer
from ..training import xgboost_trainer
from ..models.schemas import (
    ForecastPoint, HotspotPrediction, ForecastResponse,
    HotspotResponse,
)

logger = logging.getLogger(__name__)

# Alert level thresholds
ALERT_THRESHOLDS = [
    (0.0, 0.2, "Normal"),
    (0.2, 0.4, "Elevated"),
    (0.4, 0.6, "High"),
    (0.6, 0.8, "Severe"),
    (0.8, 1.0, "Critical"),
]


def _risk_to_alert_level(risk_score: float) -> str:
    """Convert a numeric risk score to an alert level string."""
    for low, high, level in ALERT_THRESHOLDS:
        if low <= risk_score < high:
            return level
    return "Critical" if risk_score >= 0.8 else "Normal"


def _risk_to_trend(trend_slope: float) -> str:
    """Convert a trend slope to a direction string."""
    if trend_slope > 0.1:
        return "rising"
    elif trend_slope < -0.1:
        return "falling"
    return "stable"


def _get_cell_for_location(lat: float, lng: float, cell_size: float = 0.1) -> Tuple[float, float]:
    """Get the grid cell coordinates for a given location."""
    cell_lat = round(lat / cell_size) * cell_size
    cell_lng = round(lng / cell_size) * cell_size
    return (cell_lat, cell_lng)


def _haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate distance in km between two points."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * \
        math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def _get_cells_in_radius(
    center_lat: float, center_lng: float, radius_km: float, cell_size: float = 0.1
) -> List[Tuple[float, float]]:
    """Get all grid cells within a radius of a center point."""
    # Convert radius to degrees (approximate)
    radius_deg = radius_km / 111.0
    cells = set()

    lat_start = math.floor((center_lat - radius_deg) / cell_size) * cell_size
    lat_end = math.ceil((center_lat + radius_deg) / cell_size) * cell_size
    lng_start = math.floor((center_lng - radius_deg) / cell_size) * cell_size
    lng_end = math.ceil((center_lng + radius_deg) / cell_size) * cell_size

    lat = lat_start
    while lat <= lat_end:
        lng = lng_start
        while lng <= lng_end:
            dist = _haversine_distance(center_lat, center_lng, lat, lng)
            if dist <= radius_km:
                cells.add((round(lat, 1), round(lng, 1)))
            lng = round(lng + cell_size, 1)
        lat = round(lat + cell_size, 1)

    return list(cells)


def _get_model_version() -> str:
    """Get the current model version string."""
    metrics = xgboost_trainer.get_training_metrics()
    return metrics.get("model_version", "untrained")


def forecast_area(
    latitude: float,
    longitude: float,
    radius_km: float = 50.0,
    forecast_hours: int = 168,
    min_risk_threshold: float = 0.3,
    include_hotspots: bool = True,
) -> ForecastResponse:
    """Generate a forecast for an area around a center point.

    Args:
        latitude: Center latitude
        longitude: Center longitude
        radius_km: Radius in km
        forecast_hours: Hours to forecast ahead
        min_risk_threshold: Minimum risk score to include in hotspots
        include_hotspots: Whether to compute hotspot predictions

    Returns:
        ForecastResponse with forecast points and hotspots
    """
    forecast_days = max(1, forecast_hours // 24)
    cell_size = 0.1

    # Get cells in radius
    cells = _get_cells_in_radius(latitude, longitude, radius_km, cell_size)

    if not cells:
        # Fall back to nearest cell
        nearest_cell = _get_cell_for_location(latitude, longitude, cell_size)
        cells = [nearest_cell]

    # Collect forecasts from all cells
    all_forecast_points = []
    all_hotspots = []
    total_risk = 0.0

    for cell_lat, cell_lng in cells:
        cell_forecast = _forecast_cell(cell_lat, cell_lng, forecast_days)
        if cell_forecast is not None:
            all_forecast_points.extend(cell_forecast)

            # Get current risk score for this cell
            risk = _predict_cell_risk(cell_lat, cell_lng)
            total_risk += risk

            if include_hotspots and risk >= min_risk_threshold:
                hotspot = _create_hotspot(cell_lat, cell_lng, risk, cell_forecast)
                if hotspot:
                    all_hotspots.append(hotspot)

    # Aggregate forecast points (average by timestamp)
    aggregated = _aggregate_forecasts(all_forecast_points)

    # Calculate overall risk
    overall_risk = total_risk / len(cells) if cells else 0.0
    overall_risk = min(1.0, max(0.0, overall_risk))

    # Sort hotspots by risk score descending
    all_hotspots.sort(key=lambda h: h.risk_score, reverse=True)

    return ForecastResponse(
        forecast_points=aggregated,
        hotspots=all_hotspots[:20],  # Top 20 hotspots
        overall_risk_score=overall_risk,
        overall_alert_level=_risk_to_alert_level(overall_risk),
        model_version=_get_model_version(),
        generated_at=datetime.now(timezone.utc).isoformat(),
        forecast_hours=forecast_hours,
        total_cells_analyzed=len(cells),
    )


def _forecast_cell(
    cell_lat: float, cell_lng: float, forecast_days: int
) -> Optional[List[ForecastPoint]]:
    """Generate forecast points for a single cell using Prophet + XGBoost.

    Args:
        cell_lat: Cell latitude
        cell_lng: Cell longitude
        forecast_days: Number of days to forecast

    Returns:
        List of ForecastPoint, or None if no model available
    """
    # Try Prophet forecast first
    prophet_forecast = prophet_trainer.forecast_cell(cell_lat, cell_lng, forecast_days)

    if prophet_forecast is not None:
        # Use Prophet forecast with XGBoost risk adjustment
        points = []
        for _, row in prophet_forecast.iterrows():
            ts = row["ds"]
            predicted = max(0, row["yhat"])
            lower = max(0, row["yhat_lower"])
            upper = max(0, row["yhat_upper"])

            # Get XGBoost risk score for this cell at this date
            risk = _predict_cell_risk_for_date(cell_lat, cell_lng, ts.date())

            points.append(ForecastPoint(
                timestamp=ts.isoformat(),
                predicted_count=float(predicted),
                lower_bound=float(lower),
                upper_bound=float(upper),
                risk_score=risk,
            ))

        return points

    # Fallback: use XGBoost-only prediction
    logger.debug(f"No Prophet model for cell ({cell_lat}, {cell_lng}), using XGBoost only")
    points = []
    base_date = datetime.now(timezone.utc)

    for day in range(forecast_days):
        ts = base_date + timedelta(days=day)
        risk = _predict_cell_risk_for_date(cell_lat, cell_lng, ts.date())

        points.append(ForecastPoint(
            timestamp=ts.isoformat(),
            predicted_count=risk * 5,  # Scale risk to count
            lower_bound=risk * 2,
            upper_bound=risk * 10,
            risk_score=risk,
        ))

    return points


def _predict_cell_risk(cell_lat: float, cell_lng: float) -> float:
    """Predict current risk score for a cell."""
    return _predict_cell_risk_for_date(cell_lat, cell_lng, datetime.now(timezone.utc).date())


def _predict_cell_risk_for_date(
    cell_lat: float, cell_lng: float, target_date: date
) -> float:
    """Predict risk score for a cell on a specific date."""
    try:
        # Get Prophet components
        components = prophet_trainer.get_cell_components(cell_lat, cell_lng)

        # Get historical data for feature engineering
        incidents = data_collector.fetch_incidents(history_days=90)
        tip_offs = data_collector.fetch_tip_offs(history_days=90)
        sos_alerts = data_collector.fetch_sos_alerts(history_days=90)
        zones = data_collector.fetch_danger_zones(history_days=90)

        # Get all cells
        all_cells = data_collector.get_all_grid_cells(history_days=90)
        if not all_cells:
            all_cells = [(cell_lat, cell_lng)]

        # Engineer features
        features = fe.engineer_features(
            cell_lat, cell_lng, target_date,
            incidents, tip_offs, sos_alerts, zones, all_cells,
            prophet_components=components,
        )

        # Predict with XGBoost
        risk = xgboost_trainer.predict_risk(features)
        return float(np.clip(risk, 0.0, 1.0))

    except Exception as e:
        logger.error(f"Risk prediction failed for ({cell_lat}, {cell_lng}): {e}")
        return 0.0


def _create_hotspot(
    cell_lat: float, cell_lng: float, risk: float,
    forecast_points: List[ForecastPoint],
) -> Optional[HotspotPrediction]:
    """Create a HotspotPrediction from cell data."""
    if not forecast_points:
        return None

    # Find peak time
    peak_point = max(forecast_points, key=lambda p: p.risk_score)

    # Calculate expected count in 24h
    next_24h = [p for p in forecast_points if (
        datetime.fromisoformat(p.timestamp) - datetime.now(timezone.utc)
    ).total_seconds() <= 86400]
    expected_count = sum(p.predicted_count for p in next_24h)

    # Calculate trend
    if len(forecast_points) >= 2:
        first_risk = forecast_points[0].risk_score
        last_risk = forecast_points[-1].risk_score
        trend_slope = (last_risk - first_risk) / len(forecast_points)
    else:
        trend_slope = 0.0

    # Contributing factors
    factors = []
    if risk > 0.6:
        factors.append("High historical incident density")
    if trend_slope > 0.05:
        factors.append("Rising trend detected")
    if risk > 0.4:
        factors.append("Elevated threat indicators")

    return HotspotPrediction(
        latitude=cell_lat,
        longitude=cell_lng,
        risk_score=risk,
        alert_level=_risk_to_alert_level(risk),
        peak_time=peak_point.timestamp,
        expected_count_24h=expected_count,
        trend_direction=_risk_to_trend(trend_slope),
        contributing_factors=factors,
    )


def _aggregate_forecasts(points: List[ForecastPoint]) -> List[ForecastPoint]:
    """Aggregate multiple cell forecasts by timestamp (average)."""
    if not points:
        return []

    by_timestamp: Dict[str, List[ForecastPoint]] = {}
    for p in points:
        by_timestamp.setdefault(p.timestamp, []).append(p)

    aggregated = []
    for ts, group in sorted(by_timestamp.items()):
        avg_count = sum(p.predicted_count for p in group) / len(group)
        avg_lower = sum(p.lower_bound for p in group) / len(group)
        avg_upper = sum(p.upper_bound for p in group) / len(group)
        avg_risk = sum(p.risk_score for p in group) / len(group)

        aggregated.append(ForecastPoint(
            timestamp=ts,
            predicted_count=avg_count,
            lower_bound=avg_lower,
            upper_bound=avg_upper,
            risk_score=min(1.0, avg_risk),
        ))

    return aggregated


def detect_hotspots(
    latitude: float,
    longitude: float,
    radius_km: float = 50.0,
    min_risk_threshold: float = 0.4,
) -> HotspotResponse:
    """Detect hotspots within a radius of a location.

    Args:
        latitude: Center latitude
        longitude: Center longitude
        radius_km: Search radius in km
        min_risk_threshold: Minimum risk score for hotspot

    Returns:
        HotspotResponse with hotspot predictions
    """
    cells = _get_cells_in_radius(latitude, longitude, radius_km)
    hotspots = []

    for cell_lat, cell_lng in cells:
        risk = _predict_cell_risk(cell_lat, cell_lng)
        if risk >= min_risk_threshold:
            forecast = _forecast_cell(cell_lat, cell_lng, forecast_days=7)
            hotspot = _create_hotspot(cell_lat, cell_lng, risk, forecast or [])
            if hotspot:
                hotspots.append(hotspot)

    hotspots.sort(key=lambda h: h.risk_score, reverse=True)

    return HotspotResponse(
        hotspots=hotspots[:30],
        total_hotspots=len(hotspots),
        generated_at=datetime.now(timezone.utc).isoformat(),
        model_version=_get_model_version(),
    )
