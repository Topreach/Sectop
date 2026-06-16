"""
XGBoost model trainer for spatio-temporal risk scoring.
Stage 2 of the hybrid model: XGBoost takes the 30-feature vector (including Prophet components)
and predicts the risk score (0.0-1.0) for each grid cell.

The XGBoost model captures:
- Non-linear interactions between features
- Feature importance for interpretability
- Spatial correlation patterns
- Temporal patterns beyond Prophet's decomposition
"""

import os
import json
import logging
import pickle
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score

logger = logging.getLogger(__name__)

# Model storage
MODEL_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "models", "xgboost")
MODEL_FILE = os.path.join(MODEL_DIR, "xgboost_model.pkl")
FEATURE_NAMES_FILE = os.path.join(MODEL_DIR, "feature_names.json")
METRICS_FILE = os.path.join(MODEL_DIR, "training_metrics.json")


def _ensure_model_dir():
    os.makedirs(MODEL_DIR, exist_ok=True)


def train_xgboost(
    X: pd.DataFrame,
    y: pd.Series,
    n_estimators: int = 200,
    max_depth: int = 6,
    learning_rate: float = 0.05,
    test_split_ratio: float = 0.2,
    force_retrain: bool = False,
) -> Dict:
    """Train the XGBoost risk scoring model.

    Args:
        X: Feature DataFrame (rows = cell-dates, columns = features)
        y: Target Series (incident_count_7d)
        n_estimators: Number of boosting rounds
        max_depth: Maximum tree depth
        learning_rate: Boosting learning rate
        test_split_ratio: Fraction of data for validation
        force_retrain: Force retrain even if model exists

    Returns:
        Dict with training metrics
    """
    _ensure_model_dir()

    if os.path.exists(MODEL_FILE) and not force_retrain:
        logger.info("XGBoost model already exists, loading metrics")
        if os.path.exists(METRICS_FILE):
            with open(METRICS_FILE, "r") as f:
                return json.load(f)
        return {"status": "exists"}

    if X.empty or y.empty:
        logger.error("Cannot train XGBoost: empty training data")
        return {"status": "failed", "error": "Empty training data"}

    try:
        import xgboost as xgb

        # Convert target to risk score (0-1) using log1p normalization
        y_risk = np.log1p(y.values)
        max_val = y_risk.max() if y_risk.max() > 0 else 1.0
        y_risk = y_risk / max_val
        y_risk = np.clip(y_risk, 0.0, 1.0)

        # Train/test split (temporal - use last 20% as test)
        split_idx = int(len(X) * (1 - test_split_ratio))
        X_train, X_test = X.iloc[:split_idx], X.iloc[split_idx:]
        y_train, y_test = y_risk[:split_idx], y_risk[split_idx:]

        # Train XGBoost regressor
        model = xgb.XGBRegressor(
            n_estimators=n_estimators,
            max_depth=max_depth,
            learning_rate=learning_rate,
            objective="reg:squarederror",
            subsample=0.8,
            colsample_bytree=0.8,
            reg_alpha=0.1,
            reg_lambda=1.0,
            min_child_weight=3,
            random_state=42,
            n_jobs=-1,
            verbosity=0,
        )

        model.fit(
            X_train, y_train,
            eval_set=[(X_test, y_test)],
            verbose=False,
        )

        # Evaluate
        y_pred = model.predict(X_test)
        mse = mean_squared_error(y_test, y_pred)
        mae = mean_absolute_error(y_test, y_pred)
        r2 = r2_score(y_test, y_pred)

        # Feature importance
        feature_importance = {}
        for name, importance in zip(X.columns, model.feature_importances_):
            feature_importance[name] = float(importance)

        # Save model
        with open(MODEL_FILE, "wb") as f:
            pickle.dump(model, f)

        # Save feature names
        with open(FEATURE_NAMES_FILE, "w") as f:
            json.dump(list(X.columns), f)

        # Save metrics
        metrics = {
            "status": "trained",
            "model_version": datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S"),
            "training_samples": len(X_train),
            "test_samples": len(X_test),
            "features": len(X.columns),
            "mse": float(mse),
            "mae": float(mae),
            "r2_score": float(r2),
            "n_estimators": n_estimators,
            "max_depth": max_depth,
            "learning_rate": learning_rate,
            "feature_importance": feature_importance,
            "trained_at": datetime.now(timezone.utc).isoformat(),
        }

        with open(METRICS_FILE, "w") as f:
            json.dump(metrics, f, indent=2)

        logger.info(
            f"XGBoost model trained: MSE={mse:.4f}, MAE={mae:.4f}, R2={r2:.4f}, "
            f"features={len(X.columns)}, samples={len(X_train)}"
        )

        return metrics

    except ImportError:
        logger.error("xgboost not installed. Install with: pip install xgboost")
        return {"status": "failed", "error": "xgboost not installed"}
    except Exception as e:
        logger.error(f"XGBoost training failed: {e}")
        return {"status": "failed", "error": str(e)}


def load_xgboost_model():
    """Load the trained XGBoost model.

    Returns:
        XGBoost model object, or None if not found.
    """
    if not os.path.exists(MODEL_FILE):
        return None
    try:
        with open(MODEL_FILE, "rb") as f:
            return pickle.load(f)
    except Exception as e:
        logger.error(f"Failed to load XGBoost model: {e}")
        return None


def get_feature_names() -> List[str]:
    """Get the list of feature names used by the model."""
    if os.path.exists(FEATURE_NAMES_FILE):
        with open(FEATURE_NAMES_FILE, "r") as f:
            return json.load(f)
    return []


def get_training_metrics() -> Dict:
    """Get the training metrics from the last training run."""
    if os.path.exists(METRICS_FILE):
        with open(METRICS_FILE, "r") as f:
            return json.load(f)
    return {"status": "not_trained"}


def predict_risk(features: Dict[str, float]) -> float:
    """Predict risk score for a single feature vector.

    Args:
        features: Dict of feature name -> value

    Returns:
        Risk score 0.0-1.0
    """
    model = load_xgboost_model()
    if model is None:
        return 0.0

    feature_names = get_feature_names()
    if not feature_names:
        return 0.0

    # Build feature vector in correct order
    X = pd.DataFrame([features])[feature_names]
    X = X.fillna(0.0)

    risk = model.predict(X)[0]
    return float(np.clip(risk, 0.0, 1.0))


def predict_batch(features_list: List[Dict[str, float]]) -> np.ndarray:
    """Predict risk scores for a batch of feature vectors.

    Args:
        features_list: List of feature dicts

    Returns:
        Array of risk scores 0.0-1.0
    """
    model = load_xgboost_model()
    if model is None:
        return np.zeros(len(features_list))

    feature_names = get_feature_names()
    if not feature_names:
        return np.zeros(len(features_list))

    X = pd.DataFrame(features_list)[feature_names]
    X = X.fillna(0.0)

    risks = model.predict(X)
    return np.clip(risks, 0.0, 1.0)
