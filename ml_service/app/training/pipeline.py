"""
Training pipeline orchestrator for the Prophet + XGBoost hybrid model.
Coordinates data collection, feature engineering, Prophet training, and XGBoost training.

Training schedule:
- Full retrain: Daily at 02:00 (low-traffic period)
- Incremental update: Every 6 hours (Prophet components only)
- On-demand: Triggered via API
"""

import os
import json
import logging
import threading
from typing import Dict, Optional
from datetime import datetime, timezone

from . import data_collector
from . import feature_engineer
from . import prophet_trainer
from . import xgboost_trainer

logger = logging.getLogger(__name__)

# Training state
_training_lock = threading.Lock()
_training_status = {
    "status": "idle",
    "started_at": None,
    "completed_at": None,
    "total_cells": 0,
    "trained_cells": 0,
    "failed_cells": 0,
    "error_message": None,
    "model_version": None,
    "metrics": None,
}


def get_training_status() -> Dict:
    """Get the current training status."""
    with _training_lock:
        return dict(_training_status)


def _update_status(**kwargs):
    """Update training status fields."""
    with _training_lock:
        _training_status.update(**kwargs)


def run_training_pipeline(
    history_days: int = 90,
    cell_size_deg: float = 0.1,
    min_incidents_per_cell: int = 3,
    prophet_seasonality_mode: str = "multiplicative",
    xgboost_n_estimators: int = 200,
    xgboost_max_depth: int = 6,
    xgboost_learning_rate: float = 0.05,
    test_split_ratio: float = 0.2,
    force_retrain: bool = False,
) -> Dict:
    """Run the full training pipeline.

    Steps:
    1. Collect historical data from PostgreSQL
    2. Identify grid cells with sufficient data
    3. Train Prophet models per cell (time-series decomposition)
    4. Engineer 30-feature vectors for each cell-date
    5. Train XGBoost model (spatio-temporal risk scoring)

    Returns:
        Dict with training results
    """
    _update_status(
        status="running",
        started_at=datetime.now(timezone.utc).isoformat(),
        completed_at=None,
        total_cells=0,
        trained_cells=0,
        failed_cells=0,
        error_message=None,
    )

    try:
        logger.info("=" * 60)
        logger.info("Starting predictive ML model training pipeline")
        logger.info(f"History: {history_days}d, Cell size: {cell_size_deg}°, "
                     f"Min incidents/cell: {min_incidents_per_cell}")

        # Step 1: Collect data
        logger.info("Step 1/5: Collecting historical data...")
        incidents = data_collector.fetch_incidents(history_days, cell_size_deg)
        tip_offs = data_collector.fetch_tip_offs(history_days)
        sos_alerts = data_collector.fetch_sos_alerts(history_days)
        zones = data_collector.fetch_danger_zones(history_days)

        logger.info(f"  Incidents: {len(incidents)} rows")
        logger.info(f"  Tip-offs: {len(tip_offs)} rows")
        logger.info(f"  SOS alerts: {len(sos_alerts)} rows")
        logger.info(f"  Danger zones: {len(zones)} rows")

        # Step 2: Identify grid cells
        logger.info("Step 2/5: Identifying grid cells...")
        all_cells = data_collector.get_all_grid_cells(
            history_days, cell_size_deg, min_incidents_per_cell
        )
        logger.info(f"  Found {len(all_cells)} qualified grid cells")

        _update_status(total_cells=len(all_cells))

        if not all_cells:
            logger.warning("No qualified grid cells found. Training XGBoost with synthetic cells.")
            # Use synthetic cells from data_collector
            all_cells = [
                (9.0, 7.0), (6.5, 3.4), (10.5, 7.4), (12.0, 8.5),
                (7.4, 3.9), (4.8, 7.0), (6.4, 7.5), (11.0, 13.0),
                (10.3, 11.0), (13.0, 5.3),
            ]
            _update_status(total_cells=len(all_cells))

        # Step 3: Train Prophet models per cell
        logger.info("Step 3/5: Training Prophet models per cell...")
        trained_cells = 0
        failed_cells = 0

        for cell_lat, cell_lng in all_cells:
            cell_incidents = incidents[
                (incidents["cell_lat"] == cell_lat) &
                (incidents["cell_lng"] == cell_lng)
            ] if not incidents.empty else pd.DataFrame()

            result = prophet_trainer.train_cell_model(
                cell_lat, cell_lng, cell_incidents,
                seasonality_mode=prophet_seasonality_mode,
                force_retrain=force_retrain,
            )

            if result and result.get("status") in ("trained", "exists"):
                trained_cells += 1
            else:
                failed_cells += 1

            _update_status(trained_cells=trained_cells, failed_cells=failed_cells)

        logger.info(f"  Prophet models: {trained_cells} trained, {failed_cells} failed")

        # Step 4: Engineer features for XGBoost
        logger.info("Step 4/5: Engineering features for XGBoost...")

        # Import pandas here for the synthetic cells case
        import pandas as pd

        X, y = feature_engineer.build_training_matrix(
            incidents, tip_offs, sos_alerts, zones, all_cells, history_days
        )

        logger.info(f"  Feature matrix: {X.shape[0]} samples, {X.shape[1]} features")

        if X.empty:
            logger.error("Empty feature matrix, cannot train XGBoost")
            _update_status(
                status="failed",
                completed_at=datetime.now(timezone.utc).isoformat(),
                error_message="Empty feature matrix",
            )
            return get_training_status()

        # Step 5: Train XGBoost
        logger.info("Step 5/5: Training XGBoost model...")
        metrics = xgboost_trainer.train_xgboost(
            X, y,
            n_estimators=xgboost_n_estimators,
            max_depth=xgboost_max_depth,
            learning_rate=xgboost_learning_rate,
            test_split_ratio=test_split_ratio,
            force_retrain=force_retrain,
        )

        model_version = metrics.get("model_version", datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S"))

        _update_status(
            status="completed",
            completed_at=datetime.now(timezone.utc).isoformat(),
            model_version=model_version,
            metrics=metrics,
        )

        logger.info("=" * 60)
        logger.info(f"Training pipeline completed successfully")
        logger.info(f"Model version: {model_version}")
        logger.info(f"Cells: {trained_cells}/{len(all_cells)} trained")
        if "r2_score" in metrics:
            logger.info(f"XGBoost R²: {metrics['r2_score']:.4f}")
        logger.info("=" * 60)

        return get_training_status()

    except Exception as e:
        logger.error(f"Training pipeline failed: {e}", exc_info=True)
        _update_status(
            status="failed",
            completed_at=datetime.now(timezone.utc).isoformat(),
            error_message=str(e),
        )
        return get_training_status()


def run_training_async(**kwargs):
    """Run the training pipeline in a background thread."""
    thread = threading.Thread(target=run_training_pipeline, kwargs=kwargs, daemon=True)
    thread.start()
    logger.info("Training pipeline started in background thread")
