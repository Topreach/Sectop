"""
Feature engineering for the predictive ML model.
Constructs the 30-feature vector used by XGBoost for spatio-temporal risk scoring.

Feature Groups:
1. Temporal (8 features): hour, day_of_week, month, is_dry_season, is_holiday,
   is_election_period, is_weekend, is_night
2. Spatial (5 features): cell_lat, cell_lng, state_encoded, lga_encoded, population_proxy
3. Historical (8 features): incident_count_7d, incident_count_14d, incident_count_30d,
   incident_severity_sum, incident_type_diversity, danger_zone_count,
   tip_off_count_7d, tip_off_threat_sum_7d, sos_alert_count_7d
4. Derived (9 features): recency_weighted_count, hotspot_distance_km, cluster_density,
   trend_slope_7d, prophet_trend, prophet_seasonal, prophet_upper_bound
"""

import logging
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta, date, timezone

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# Nigerian public holidays (fixed dates)
NIGERIAN_HOLIDAYS = [
    (1, 1),    # New Year's Day
    (5, 1),    # Workers' Day
    (5, 29),   # Democracy Day
    (10, 1),   # Independence Day
    (12, 25),  # Christmas Day
    (12, 26),  # Boxing Day
]

# Nigerian dry season months (Nov-Mar)
DRY_SEASON_MONTHS = {11, 12, 1, 2, 3}

# Election periods (approximate months)
ELECTION_MONTHS = {2, 3}  # General elections typically Feb/Mar


def _is_holiday(d: date) -> bool:
    """Check if a date is a Nigerian public holiday."""
    if (d.month, d.day) in NIGERIAN_HOLIDAYS:
        return True
    # Ramadan/Edi holidays vary by year - approximate
    return False


def _haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate haversine distance in km between two points."""
    R = 6371.0
    dlat = np.radians(lat2 - lat1)
    dlng = np.radians(lng2 - lng1)
    a = np.sin(dlat / 2) ** 2 + np.cos(np.radians(lat1)) * \
        np.cos(np.radians(lat2)) * np.sin(dlng / 2) ** 2
    c = 2 * np.arctan2(np.sqrt(a), np.sqrt(1 - a))
    return R * c


def engineer_features(
    cell_lat: float,
    cell_lng: float,
    target_date: date,
    incident_history: pd.DataFrame,
    tip_off_history: pd.DataFrame,
    sos_history: pd.DataFrame,
    zone_history: pd.DataFrame,
    all_cells: List[Tuple[float, float]],
    prophet_components: Optional[Dict[str, float]] = None,
) -> Dict[str, float]:
    """Engineer the full 30-feature vector for a single cell on a target date.

    Args:
        cell_lat: Cell latitude center
        cell_lng: Cell longitude center
        target_date: The date to engineer features for
        incident_history: DataFrame with incident history
        tip_off_history: DataFrame with tip-off history
        sos_history: DataFrame with SOS alert history
        zone_history: DataFrame with danger zone history
        all_cells: List of all (lat, lng) cell coordinates
        prophet_components: Optional Prophet trend/seasonal components

    Returns:
        Dict of feature name -> value
    """
    features = {}

    # ── Temporal Features (8) ──
    dt = datetime.combine(target_date, datetime.min.time())
    features["hour"] = 12.0  # Default noon for daily aggregation
    features["day_of_week"] = float(target_date.weekday())
    features["month"] = float(target_date.month)
    features["is_dry_season"] = 1.0 if target_date.month in DRY_SEASON_MONTHS else 0.0
    features["is_holiday"] = 1.0 if _is_holiday(target_date) else 0.0
    features["is_election_period"] = 1.0 if target_date.month in ELECTION_MONTHS else 0.0
    features["is_weekend"] = 1.0 if target_date.weekday() >= 5 else 0.0
    features["is_night"] = 0.0  # Daily aggregation

    # ── Spatial Features (5) ──
    features["cell_lat"] = cell_lat
    features["cell_lng"] = cell_lng
    # State/LGA encoding - simplified to grid-based encoding
    features["state_encoded"] = hash(f"{cell_lat:.1f},{cell_lng:.1f}") % 1000
    features["lga_encoded"] = hash(f"{cell_lat:.2f},{cell_lng:.2f}") % 10000
    # Population proxy based on known Nigerian population centers
    features["population_proxy"] = _population_proxy(cell_lat, cell_lng)

    # ── Historical Features (9) ──
    td_7 = timedelta(days=7)
    td_14 = timedelta(days=14)
    td_30 = timedelta(days=30)

    # Filter incident history for this cell
    cell_incidents = incident_history[
        (incident_history["cell_lat"] == cell_lat) &
        (incident_history["cell_lng"] == cell_lng)
    ] if not incident_history.empty else pd.DataFrame()

    if not cell_incidents.empty:
        cell_incidents = cell_incidents.copy()
        cell_incidents["date"] = pd.to_datetime(cell_incidents["date"])

        mask_7d = cell_incidents["date"] >= pd.Timestamp(target_date - td_7)
        mask_14d = cell_incidents["date"] >= pd.Timestamp(target_date - td_14)
        mask_30d = cell_incidents["date"] >= pd.Timestamp(target_date - td_30)

        features["incident_count_7d"] = float(mask_7d.sum())
        features["incident_count_14d"] = float(mask_14d.sum())
        features["incident_count_30d"] = float(mask_30d.sum())
        features["incident_severity_sum"] = float(
            cell_incidents.loc[mask_30d, "severity_sum"].sum()
            if "severity_sum" in cell_incidents.columns else 0
        )
        features["incident_type_diversity"] = float(
            cell_incidents.loc[mask_30d, "incident_type_diversity"].sum()
            if "incident_type_diversity" in cell_incidents.columns else 0
        )
    else:
        features["incident_count_7d"] = 0.0
        features["incident_count_14d"] = 0.0
        features["incident_count_30d"] = 0.0
        features["incident_severity_sum"] = 0.0
        features["incident_type_diversity"] = 0.0

    # Danger zone count
    cell_zones = zone_history[
        (zone_history["cell_lat"] == cell_lat) &
        (zone_history["cell_lng"] == cell_lng)
    ] if not zone_history.empty else pd.DataFrame()

    if not cell_zones.empty:
        cell_zones = cell_zones.copy()
        cell_zones["date"] = pd.to_datetime(cell_zones["date"])
        features["danger_zone_count"] = float(
            (cell_zones["date"] >= pd.Timestamp(target_date - td_30)).sum()
        )
    else:
        features["danger_zone_count"] = 0.0

    # Tip-off features
    cell_tipoffs = tip_off_history[
        (tip_off_history["cell_lat"] == cell_lat) &
        (tip_off_history["cell_lng"] == cell_lng)
    ] if not tip_off_history.empty else pd.DataFrame()

    if not cell_tipoffs.empty:
        cell_tipoffs = cell_tipoffs.copy()
        cell_tipoffs["date"] = pd.to_datetime(cell_tipoffs["date"])
        mask_7d = cell_tipoffs["date"] >= pd.Timestamp(target_date - td_7)
        features["tip_off_count_7d"] = float(mask_7d.sum())
        features["tip_off_threat_sum_7d"] = float(
            cell_tipoffs.loc[mask_7d, "threat_sum"].sum()
            if "threat_sum" in cell_tipoffs.columns else 0
        )
    else:
        features["tip_off_count_7d"] = 0.0
        features["tip_off_threat_sum_7d"] = 0.0

    # SOS alert features
    cell_sos = sos_history[
        (sos_history["cell_lat"] == cell_lat) &
        (sos_history["cell_lng"] == cell_lng)
    ] if not sos_history.empty else pd.DataFrame()

    if not cell_sos.empty:
        cell_sos = cell_sos.copy()
        cell_sos["date"] = pd.to_datetime(cell_sos["date"])
        features["sos_alert_count_7d"] = float(
            (cell_sos["date"] >= pd.Timestamp(target_date - td_7)).sum()
        )
    else:
        features["sos_alert_count_7d"] = 0.0

    # ── Derived Features (9) ──
    # Recency-weighted count (more weight to recent incidents)
    if not cell_incidents.empty:
        recency_weighted = 0.0
        for _, row in cell_incidents.iterrows():
            days_ago = (target_date - row["date"].date()).days
            if 0 <= days_ago <= 30:
                weight = np.exp(-days_ago / 7.0)  # Exponential decay with 7-day half-life
                recency_weighted += weight * row.get("incident_count", 1)
        features["recency_weighted_count"] = recency_weighted
    else:
        features["recency_weighted_count"] = 0.0

    # Hotspot distance - distance to nearest high-risk cell
    min_dist = float("inf")
    for other_lat, other_lng in all_cells:
        if other_lat == cell_lat and other_lng == cell_lng:
            continue
        dist = _haversine(cell_lat, cell_lng, other_lat, other_lng)
        if dist < min_dist:
            min_dist = dist
    features["hotspot_distance_km"] = min_dist if min_dist != float("inf") else 100.0

    # Cluster density - number of nearby cells with incidents
    cluster_count = 0
    for other_lat, other_lng in all_cells:
        if other_lat == cell_lat and other_lng == cell_lng:
            continue
        dist = _haversine(cell_lat, cell_lng, other_lat, other_lng)
        if dist < 50.0:  # Within 50km
            cluster_count += 1
    features["cluster_density"] = float(cluster_count)

    # Trend slope over last 7 days
    if not cell_incidents.empty:
        recent_7d = cell_incidents[
            cell_incidents["date"] >= pd.Timestamp(target_date - td_7)
        ]
        if len(recent_7d) >= 2:
            # Simple linear regression slope
            x = np.arange(len(recent_7d))
            y = recent_7d["incident_count"].values
            slope = np.polyfit(x, y, 1)[0] if len(x) > 1 else 0.0
            features["trend_slope_7d"] = float(slope)
        else:
            features["trend_slope_7d"] = 0.0
    else:
        features["trend_slope_7d"] = 0.0

    # Prophet components (if available)
    if prophet_components:
        features["prophet_trend"] = prophet_components.get("trend", 0.0)
        features["prophet_seasonal"] = prophet_components.get("seasonal", 0.0)
        features["prophet_upper_bound"] = prophet_components.get("upper_bound", 0.0)
    else:
        features["prophet_trend"] = 0.0
        features["prophet_seasonal"] = 0.0
        features["prophet_upper_bound"] = 0.0

    return features


def _population_proxy(lat: float, lng: float) -> float:
    """Estimate population density proxy based on known Nigerian cities.

    Returns a value 0.0-1.0 representing relative population density.
    """
    # Major Nigerian cities with approximate coordinates and relative population
    cities = [
        (6.5244, 3.3792, 1.0),    # Lagos
        (7.3775, 3.9470, 0.8),    # Ibadan
        (9.0765, 7.3986, 0.7),    # Abuja
        (12.0022, 8.5920, 0.6),   # Kano
        (10.5105, 7.4165, 0.5),   # Kaduna
        (4.8156, 7.0498, 0.4),    # Port Harcourt
        (6.4413, 7.4908, 0.4),    # Enugu
        (11.8314, 13.1514, 0.3),  # Maiduguri
        (4.9517, 8.3220, 0.3),    # Calabar
        (7.1557, 3.3451, 0.3),    # Abeokuta
        (8.4856, 4.5516, 0.3),    # Ilorin
        (10.2734, 11.8068, 0.3),  # Damaturu
        (13.0622, 5.2335, 0.2),   # Sokoto
        (12.4495, 4.5250, 0.2),   # Gusau
        (6.8400, 7.0000, 0.2),    # Nsukka
    ]

    max_weight = 0.0
    for city_lat, city_lng, weight in cities:
        dist = _haversine(lat, lng, city_lat, city_lng)
        # Gaussian decay with 100km radius
        cell_weight = weight * np.exp(-(dist ** 2) / (2 * (100 ** 2)))
        if cell_weight > max_weight:
            max_weight = cell_weight

    return max_weight


def build_training_matrix(
    incidents: pd.DataFrame,
    tip_offs: pd.DataFrame,
    sos_alerts: pd.DataFrame,
    zones: pd.DataFrame,
    all_cells: List[Tuple[float, float]],
    history_days: int = 90,
) -> Tuple[pd.DataFrame, pd.Series]:
    """Build the full training matrix (X, y) for XGBoost.

    Args:
        incidents: Incident history DataFrame
        tip_offs: Tip-off history DataFrame
        sos_alerts: SOS alert history DataFrame
        zones: Danger zone history DataFrame
        all_cells: List of all grid cell coordinates
        history_days: Number of days of history

    Returns:
        X: Feature DataFrame (rows = cell-dates)
        y: Target Series (incident_count for next 7 days)
    """
    rows = []
    targets = []

    end_date = datetime.now(timezone.utc).date()
    start_date = end_date - timedelta(days=history_days)

    for cell_lat, cell_lng in all_cells:
        # For each date in history, engineer features
        current = start_date
        while current < end_date:
            features = engineer_features(
                cell_lat, cell_lng, current,
                incidents, tip_offs, sos_alerts, zones, all_cells,
            )

            # Target: incident count in the next 7 days for this cell
            future_start = current + timedelta(days=1)
            future_end = current + timedelta(days=8)

            cell_incidents = incidents[
                (incidents["cell_lat"] == cell_lat) &
                (incidents["cell_lng"] == cell_lng)
            ] if not incidents.empty else pd.DataFrame()

            target = 0.0
            if not cell_incidents.empty:
                cell_incidents = cell_incidents.copy()
                cell_incidents["date"] = pd.to_datetime(cell_incidents["date"])
                future_mask = (
                    (cell_incidents["date"] >= pd.Timestamp(future_start)) &
                    (cell_incidents["date"] < pd.Timestamp(future_end))
                )
                target = float(cell_incidents.loc[future_mask, "incident_count"].sum())

            rows.append(features)
            targets.append(target)
            current += timedelta(days=1)

    X = pd.DataFrame(rows)
    y = pd.Series(targets, name="incident_count_7d")

    logger.info(f"Built training matrix: X={X.shape}, y={y.shape}")
    return X, y
