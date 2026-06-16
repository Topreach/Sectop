"""
Prophet model trainer for time-series decomposition of incident counts.
Trains one Prophet model per grid cell to capture trend, seasonality, and holiday effects.

Stage 1 of the hybrid model: Prophet decomposes the time series into:
- Trend component (long-term direction)
- Weekly seasonality (day-of-week patterns)
- Yearly seasonality (month-of-year patterns)
- Holiday effects (Nigerian public holidays)
"""

import os
import json
import logging
import pickle
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta, timezone

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# Model storage directory
MODEL_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "models", "prophet")


def _ensure_model_dir():
    """Ensure the Prophet model directory exists."""
    os.makedirs(MODEL_DIR, exist_ok=True)


def _model_path(cell_lat: float, cell_lng: float) -> str:
    """Get the file path for a cell's Prophet model."""
    return os.path.join(MODEL_DIR, f"prophet_{cell_lat:.1f}_{cell_lng:.1f}.pkl")


def _components_path(cell_lat: float, cell_lng: float) -> str:
    """Get the file path for a cell's Prophet components cache."""
    return os.path.join(MODEL_DIR, f"components_{cell_lat:.1f}_{cell_lng:.1f}.json")


def train_cell_model(
    cell_lat: float,
    cell_lng: float,
    incident_history: pd.DataFrame,
    seasonality_mode: str = "multiplicative",
    force_retrain: bool = False,
) -> Optional[Dict]:
    """Train a Prophet model for a single grid cell.

    Args:
        cell_lat: Cell latitude center
        cell_lng: Cell longitude center
        incident_history: DataFrame with incident history for this cell
        seasonality_mode: 'additive' or 'multiplicative'
        force_retrain: Force retrain even if model exists

    Returns:
        Dict with training metrics, or None if insufficient data
    """
    _ensure_model_dir()

    # Check if model already exists
    model_file = _model_path(cell_lat, cell_lng)
    if os.path.exists(model_file) and not force_retrain:
        logger.info(f"Prophet model already exists for cell ({cell_lat}, {cell_lng})")
        return {"status": "exists", "cell_lat": cell_lat, "cell_lng": cell_lng}

    if incident_history.empty:
        logger.warning(f"No incident data for cell ({cell_lat}, {cell_lng})")
        return None

    # Prepare Prophet input: ds (date), y (incident_count)
    prophet_df = incident_history.copy()
    prophet_df["ds"] = pd.to_datetime(prophet_df["date"])
    prophet_df["y"] = prophet_df["incident_count"].values

    # Aggregate by date (in case of multiple rows per date)
    prophet_df = prophet_df.groupby("ds").agg({"y": "sum"}).reset_index()

    if len(prophet_df) < 7:
        logger.warning(f"Insufficient data for cell ({cell_lat}, {cell_lng}): {len(prophet_df)} days")
        return None

    try:
        from prophet import Prophet

        # Configure Prophet with Nigerian holiday calendar
        model = Prophet(
            yearly_seasonality=True,
            weekly_seasonality=True,
            daily_seasonality=False,
            seasonality_mode=seasonality_mode,
            changepoint_prior_scale=0.05,
            seasonality_prior_scale=10.0,
            holidays_prior_scale=10.0,
            interval_width=0.95,
        )

        # Add Nigerian public holidays as regressors
        _add_nigerian_holidays(model, prophet_df)

        # Fit the model
        model.fit(prophet_df)

        # Save model
        with open(model_file, "wb") as f:
            pickle.dump(model, f)

        # Generate future dataframe for component extraction
        future = model.make_future_dataframe(periods=30, freq="D")
        forecast = model.predict(future)

        # Extract and cache components for the last known date
        components = {
            "trend": float(forecast["trend"].iloc[-1]),
            "seasonal": float(
                forecast["weekly"].iloc[-1] +
                forecast["yearly"].iloc[-1]
            ),
            "upper_bound": float(forecast["yhat_upper"].iloc[-1]),
            "lower_bound": float(forecast["yhat_lower"].iloc[-1]),
        }
        with open(_components_path(cell_lat, cell_lng), "w") as f:
            json.dump(components, f)

        logger.info(
            f"Trained Prophet model for cell ({cell_lat}, {cell_lng}): "
            f"{len(prophet_df)} days, trend={components['trend']:.2f}"
        )

        return {
            "status": "trained",
            "cell_lat": cell_lat,
            "cell_lng": cell_lng,
            "data_points": len(prophet_df),
            "trend": components["trend"],
        }

    except Exception as e:
        logger.error(f"Failed to train Prophet model for cell ({cell_lat}, {cell_lng}): {e}")
        return None


def load_cell_model(cell_lat: float, cell_lng: float):
    """Load a trained Prophet model for a cell.

    Returns:
        Prophet model object, or None if not found.
    """
    model_file = _model_path(cell_lat, cell_lng)
    if not os.path.exists(model_file):
        return None
    try:
        with open(model_file, "rb") as f:
            return pickle.load(f)
    except Exception as e:
        logger.error(f"Failed to load Prophet model for ({cell_lat}, {cell_lng}): {e}")
        return None


def get_cell_components(cell_lat: float, cell_lng: float) -> Optional[Dict[str, float]]:
    """Get cached Prophet components for a cell."""
    comp_file = _components_path(cell_lat, cell_lng)
    if not os.path.exists(comp_file):
        return None
    try:
        with open(comp_file, "r") as f:
            return json.load(f)
    except Exception:
        return None


def forecast_cell(
    cell_lat: float,
    cell_lng: float,
    periods: int = 30,
) -> Optional[pd.DataFrame]:
    """Generate forecast for a single cell using its trained Prophet model.

    Args:
        cell_lat: Cell latitude center
        cell_lng: Cell longitude center
        periods: Number of days to forecast

    Returns:
        DataFrame with forecast, or None if model not found
    """
    model = load_cell_model(cell_lat, cell_lng)
    if model is None:
        return None

    future = model.make_future_dataframe(periods=periods, freq="D")
    forecast = model.predict(future)
    return forecast


def get_trained_cells() -> List[Tuple[float, float]]:
    """Get list of all cells with trained Prophet models."""
    _ensure_model_dir()
    cells = []
    for fname in os.listdir(MODEL_DIR):
        if fname.startswith("prophet_") and fname.endswith(".pkl"):
            parts = fname.replace(".pkl", "").split("_")
            if len(parts) >= 3:
                try:
                    lat = float(parts[1])
                    lng = float(parts[2])
                    cells.append((lat, lng))
                except ValueError:
                    continue
    return cells


def get_training_metrics() -> Dict:
    """Get aggregate training metrics across all cells."""
    cells = get_trained_cells()
    return {
        "total_cells_trained": len(cells),
        "cells": [{"lat": c[0], "lng": c[1]} for c in cells],
    }


def _add_nigerian_holidays(model, prophet_df):
    """Add Nigerian public holidays as Prophet regressors."""
    holidays = pd.DataFrame({
        "holiday": "nigeria_public_holiday",
        "ds": pd.to_datetime([
            # Fixed-date holidays for the years in the data
        ]),
        "lower_window": 0,
        "upper_window": 0,
    })

    # Generate holidays for years present in data
    if not prophet_df.empty:
        years = prophet_df["ds"].dt.year.unique()
        holiday_dates = []
        for year in years:
            holiday_dates.extend([
                f"{year}-01-01",   # New Year
                f"{year}-05-01",   # Workers' Day
                f"{year}-05-29",   # Democracy Day
                f"{year}-10-01",   # Independence Day
                f"{year}-12-25",   # Christmas
                f"{year}-12-26",   # Boxing Day
            ])
        holidays = pd.DataFrame({
            "holiday": "nigeria_public_holiday",
            "ds": pd.to_datetime(holiday_dates),
            "lower_window": 0,
            "upper_window": 1,
        })

    if not holidays.empty:
        model.holidays = holidays
