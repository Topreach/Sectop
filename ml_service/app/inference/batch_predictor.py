"""
Batch prediction module for the predictive ML model.
Handles bulk forecasting across multiple areas and scheduled prediction jobs.
"""

import logging
import time
from typing import List
from datetime import datetime, timezone

from ..models.schemas import ForecastRequest, ForecastResponse, BatchForecastResponse
from .predictor import forecast_area

logger = logging.getLogger(__name__)


def batch_forecast(requests: List[ForecastRequest]) -> BatchForecastResponse:
    """Run forecasts for multiple areas in batch.

    Args:
        requests: List of ForecastRequest objects

    Returns:
        BatchForecastResponse with individual results
    """
    start = time.time()
    results = []

    for req in requests:
        try:
            result = forecast_area(
                latitude=req.latitude or 9.0,  # Default to Abuja center
                longitude=req.longitude or 7.0,
                radius_km=req.radius_km or 50.0,
                forecast_hours=req.forecast_hours,
                min_risk_threshold=req.min_risk_threshold,
                include_hotspots=req.include_hotspots,
            )
            results.append(result)
        except Exception as e:
            logger.error(f"Batch forecast failed for request: {e}")
            results.append(ForecastResponse(
                forecast_points=[],
                hotspots=[],
                overall_risk_score=0.0,
                overall_alert_level="Normal",
                model_version="error",
                generated_at=datetime.now(timezone.utc).isoformat(),
                forecast_hours=req.forecast_hours,
                total_cells_analyzed=0,
            ))

    total_time = (time.time() - start) * 1000

    return BatchForecastResponse(
        results=results,
        total_time_ms=total_time,
    )


def forecast_all_nigerian_states() -> List[ForecastResponse]:
    """Generate forecasts for all 36 Nigerian states + FCT.

    Returns:
        List of ForecastResponse, one per state
    """
    # Nigerian state capitals (approximate coordinates)
    state_capitals = [
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

    results = []
    for state_name, lat, lng in state_capitals:
        try:
            result = forecast_area(
                latitude=lat,
                longitude=lng,
                radius_km=100.0,  # 100km covers most of each state
                forecast_hours=168,  # 7 days
                min_risk_threshold=0.3,
                include_hotspots=True,
            )
            results.append(result)
            logger.info(f"Forecast for {state_name}: risk={result.overall_risk_score:.2f}, "
                         f"hotspots={len(result.hotspots)}")
        except Exception as e:
            logger.error(f"Forecast failed for {state_name}: {e}")

    return results
