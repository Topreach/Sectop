"""
Data collector for the predictive ML model.
Queries PostgreSQL for historical incidents, tip-offs, SOS alerts, and danger zones.
Aggregates data into grid cells for Prophet + XGBoost training.
"""

import os
import logging
from typing import List, Dict, Tuple, Optional
from datetime import datetime, timedelta, timezone

import pandas as pd
import numpy as np

logger = logging.getLogger(__name__)

# Database connection parameters from environment
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "danger-emergence-db"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "danger_emergence"),
    "user": os.getenv("DB_USERNAME", "postgres"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
}


def _get_connection():
    """Create a new database connection."""
    import psycopg2
    return psycopg2.connect(**DB_CONFIG)


def _grid_cell_key(lat: float, lng: float, cell_size_deg: float) -> Tuple[float, float]:
    """Convert lat/lng to grid cell center coordinates."""
    cell_lat = round(lat / cell_size_deg) * cell_size_deg
    cell_lng = round(lng / cell_size_deg) * cell_size_deg
    return (cell_lat, cell_lng)


def fetch_incidents(
    history_days: int = 90,
    cell_size_deg: float = 0.1,
) -> pd.DataFrame:
    """Fetch historical incidents and aggregate into grid cells by day.

    Returns:
        DataFrame with columns: [cell_lat, cell_lng, date, incident_count,
        severity_sum, incident_type_diversity]
    """
    since = datetime.now(timezone.utc) - timedelta(days=history_days)

    query = """
        SELECT
            i.latitude,
            i.longitude,
            i.severity,
            i.incident_type,
            i.occurred_at
        FROM incidents i
        WHERE i.occurred_at >= %s
          AND i.latitude IS NOT NULL
          AND i.longitude IS NOT NULL
          AND i.status != 'dismissed'
        ORDER BY i.occurred_at ASC
    """

    try:
        conn = _get_connection()
        df = pd.read_sql_query(query, conn, params=(since,))
        conn.close()
    except Exception as e:
        logger.warning(f"Failed to fetch incidents from DB: {e}. Using synthetic data.")
        return _generate_synthetic_incidents(history_days, cell_size_deg)

    if df.empty:
        logger.warning("No incidents found in DB. Using synthetic data.")
        return _generate_synthetic_incidents(history_days, cell_size_deg)

    # Map severity to numeric
    severity_map = {"low": 1, "medium": 2, "high": 3, "critical": 4}
    df["severity_num"] = df["severity"].str.lower().map(severity_map).fillna(1)

    # Assign grid cells
    df["cell_lat"] = (df["latitude"] / cell_size_deg).round() * cell_size_deg
    df["cell_lng"] = (df["longitude"] / cell_size_deg).round() * cell_size_deg
    df["date"] = df["occurred_at"].dt.date

    # Aggregate by cell + date
    aggregated = df.groupby(["cell_lat", "cell_lng", "date"]).agg(
        incident_count=("id", "count"),
        severity_sum=("severity_num", "sum"),
        incident_type_diversity=("incident_type", "nunique"),
    ).reset_index()

    aggregated["date"] = pd.to_datetime(aggregated["date"])
    return aggregated


def fetch_tip_offs(history_days: int = 90) -> pd.DataFrame:
    """Fetch historical tip-offs for threat score aggregation.

    Returns:
        DataFrame with columns: [cell_lat, cell_lng, date, tip_off_count, threat_sum]
    """
    since = datetime.now(timezone.utc) - timedelta(days=history_days)

    query = """
        SELECT
            t.latitude,
            t.longitude,
            t.threat_score,
            t.occurred_at
        FROM tip_offs t
        WHERE t.occurred_at >= %s
          AND t.latitude IS NOT NULL
          AND t.longitude IS NOT NULL
          AND t.status != 'dismissed'
        ORDER BY t.occurred_at ASC
    """

    try:
        conn = _get_connection()
        df = pd.read_sql_query(query, conn, params=(since,))
        conn.close()
    except Exception as e:
        logger.warning(f"Failed to fetch tip-offs from DB: {e}. Using empty DataFrame.")
        return pd.DataFrame(columns=["cell_lat", "cell_lng", "date", "tip_off_count", "threat_sum"])

    if df.empty:
        return pd.DataFrame(columns=["cell_lat", "cell_lng", "date", "tip_off_count", "threat_sum"])

    df["threat_score"] = df["threat_score"].fillna(0.5)
    df["cell_lat"] = (df["latitude"] / 0.1).round() * 0.1
    df["cell_lng"] = (df["longitude"] / 0.1).round() * 0.1
    df["date"] = pd.to_datetime(df["occurred_at"].dt.date)

    aggregated = df.groupby(["cell_lat", "cell_lng", "date"]).agg(
        tip_off_count=("threat_score", "count"),
        threat_sum=("threat_score", "sum"),
    ).reset_index()

    return aggregated


def fetch_sos_alerts(history_days: int = 90) -> pd.DataFrame:
    """Fetch historical SOS alerts for count aggregation.

    Returns:
        DataFrame with columns: [cell_lat, cell_lng, date, sos_alert_count]
    """
    since = datetime.now(timezone.utc) - timedelta(days=history_days)

    query = """
        SELECT
            a.latitude,
            a.longitude,
            a.created_at
        FROM sos_alerts a
        WHERE a.created_at >= %s
          AND a.latitude IS NOT NULL
          AND a.longitude IS NOT NULL
        ORDER BY a.created_at ASC
    """

    try:
        conn = _get_connection()
        df = pd.read_sql_query(query, conn, params=(since,))
        conn.close()
    except Exception as e:
        logger.warning(f"Failed to fetch SOS alerts from DB: {e}. Using empty DataFrame.")
        return pd.DataFrame(columns=["cell_lat", "cell_lng", "date", "sos_alert_count"])

    if df.empty:
        return pd.DataFrame(columns=["cell_lat", "cell_lng", "date", "sos_alert_count"])

    df["cell_lat"] = (df["latitude"] / 0.1).round() * 0.1
    df["cell_lng"] = (df["longitude"] / 0.1).round() * 0.1
    df["date"] = pd.to_datetime(df["created_at"].dt.date)

    aggregated = df.groupby(["cell_lat", "cell_lng", "date"]).agg(
        sos_alert_count=("id", "count"),
    ).reset_index()

    return aggregated


def fetch_danger_zones(history_days: int = 90) -> pd.DataFrame:
    """Fetch historical danger zones.

    Returns:
        DataFrame with columns: [cell_lat, cell_lng, date, danger_zone_count]
    """
    since = datetime.now(timezone.utc) - timedelta(days=history_days)

    query = """
        SELECT
            z.latitude,
            z.longitude,
            z.created_at
        FROM zones z
        WHERE z.created_at >= %s
          AND z.type = 'hazard'
          AND z.latitude IS NOT NULL
          AND z.longitude IS NOT NULL
        ORDER BY z.created_at ASC
    """

    try:
        conn = _get_connection()
        df = pd.read_sql_query(query, conn, params=(since,))
        conn.close()
    except Exception as e:
        logger.warning(f"Failed to fetch danger zones from DB: {e}. Using empty DataFrame.")
        return pd.DataFrame(columns=["cell_lat", "cell_lng", "date", "danger_zone_count"])

    if df.empty:
        return pd.DataFrame(columns=["cell_lat", "cell_lng", "date", "danger_zone_count"])

    df["cell_lat"] = (df["latitude"] / 0.1).round() * 0.1
    df["cell_lng"] = (df["longitude"] / 0.1).round() * 0.1
    df["date"] = pd.to_datetime(df["created_at"].dt.date)

    aggregated = df.groupby(["cell_lat", "cell_lng", "date"]).agg(
        danger_zone_count=("id", "count"),
    ).reset_index()

    return aggregated


def get_all_grid_cells(
    history_days: int = 90,
    cell_size_deg: float = 0.1,
    min_incidents: int = 3,
) -> List[Tuple[float, float]]:
    """Get all grid cells that have enough historical data for training.

    Returns:
        List of (cell_lat, cell_lng) tuples.
    """
    incidents = fetch_incidents(history_days, cell_size_deg)
    if incidents.empty:
        return []

    cell_counts = incidents.groupby(["cell_lat", "cell_lng"]).size().reset_index(name="count")
    qualified = cell_counts[cell_counts["count"] >= min_incidents]
    return list(zip(qualified["cell_lat"], qualified["cell_lng"]))


def _generate_synthetic_incidents(history_days: int, cell_size_deg: float) -> pd.DataFrame:
    """Generate synthetic incident data for development/testing when DB is unavailable."""
    np.random.seed(42)
    rows = []

    # Nigeria bounding box approximate
    nigeria_cells = [
        (9.0, 7.0),   # Abuja
        (6.5, 3.4),   # Lagos
        (10.5, 7.4),  # Kaduna
        (12.0, 8.5),  # Kano
        (7.4, 3.9),   # Ibadan
        (4.8, 7.0),   # Port Harcourt
        (6.4, 7.5),   # Enugu
        (11.0, 13.0), # Maiduguri
        (10.3, 11.0), # Damaturu
        (13.0, 5.3),  # Sokoto
    ]

    incident_types = ["kidnapping", "terrorism", "banditry", "armed_robbery",
                      "suspicious_activity", "herdsmen_attack", "cult_violence",
                      "ritual_killings", "political_violence", "communal_clash"]

    base_date = datetime.now(timezone.utc) - timedelta(days=history_days)

    for cell_lat, cell_lng in nigeria_cells:
        # Each cell has a base incident rate
        base_rate = np.random.uniform(0.5, 3.0)
        for day_offset in range(history_days):
            date = base_date + timedelta(days=day_offset)
            # Add weekly seasonality (more on weekends)
            day_of_week = date.weekday()
            weekly_factor = 1.5 if day_of_week >= 5 else 1.0
            # Add random noise
            noise = np.random.poisson(base_rate * weekly_factor)
            if noise > 0:
                for _ in range(noise):
                    rows.append({
                        "latitude": cell_lat + np.random.uniform(-cell_size_deg/2, cell_size_deg/2),
                        "longitude": cell_lng + np.random.uniform(-cell_size_deg/2, cell_size_deg/2),
                        "severity": np.random.choice(["low", "medium", "high", "critical"],
                                                      p=[0.3, 0.4, 0.2, 0.1]),
                        "incident_type": np.random.choice(incident_types),
                        "occurred_at": date + timedelta(hours=np.random.randint(0, 24)),
                    })

    df = pd.DataFrame(rows)
    severity_map = {"low": 1, "medium": 2, "high": 3, "critical": 4}
    df["severity_num"] = df["severity"].map(severity_map)
    df["cell_lat"] = (df["latitude"] / cell_size_deg).round() * cell_size_deg
    df["cell_lng"] = (df["longitude"] / cell_size_deg).round() * cell_size_deg
    df["date"] = pd.to_datetime(df["occurred_at"].dt.date)

    aggregated = df.groupby(["cell_lat", "cell_lng", "date"]).agg(
        incident_count=("severity_num", "count"),
        severity_sum=("severity_num", "sum"),
        incident_type_diversity=("incident_type", "nunique"),
    ).reset_index()

    return aggregated
