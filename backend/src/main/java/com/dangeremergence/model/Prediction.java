package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * JPA entity for storing prediction results from the ML service.
 *
 * Each row represents a single hotspot prediction for a grid cell
 * at a specific forecast time. Used for historical analysis,
 * audit trail, and offline fallback for the frontend.
 */
@Entity
@Table(name = "predictions", indexes = {
    @Index(name = "idx_prediction_cell", columnList = "cellLat,cellLng"),
    @Index(name = "idx_prediction_forecast_time", columnList = "forecastTime"),
    @Index(name = "idx_prediction_risk_score", columnList = "riskScore"),
    @Index(name = "idx_prediction_created_at", columnList = "createdAt")
})
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
public class Prediction {

    @Id
    @Column(length = 36, nullable = false)
    private String id;

    /** Latitude of the grid cell center (0.1-degree grid). */
    @Column(nullable = false)
    private double cellLat;

    /** Longitude of the grid cell center (0.1-degree grid). */
    @Column(nullable = false)
    private double cellLng;

    /** State name (e.g., "Borno", "Kaduna"). */
    @Column(length = 100)
    private String state;

    /** Local Government Area name. */
    @Column(length = 100)
    private String lga;

    /** Risk score 0.0–1.0 from the ML model. */
    @Column(nullable = false)
    private double riskScore;

    /** Alert level: Normal, Elevated, High, Severe, Critical. */
    @Column(length = 20, nullable = false)
    private String alertLevel;

    /** Predicted incident count for the next 24 hours. */
    @Column(nullable = false)
    private double expectedCount24h;

    /** Trend direction: rising, falling, or stable. */
    @Column(length = 10, nullable = false)
    private String trendDirection;

    /** Peak time for the predicted activity (ISO-8601). */
    @Column(length = 30)
    private String peakTime;

    /** Comma-separated list of contributing factors. */
    @Column(length = 500)
    private String contributingFactors;

    /** The forecast time this prediction applies to. */
    @Column(nullable = false)
    private LocalDateTime forecastTime;

    /** When this prediction was created/stored. */
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    /** Model version that generated this prediction. */
    @Column(length = 20)
    private String modelVersion;

    @PrePersist
    protected void onCreate() {
        if (id == null || id.isBlank()) {
            id = java.util.UUID.randomUUID().toString();
        }
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }

    // --- Getters and Setters ---

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public double getCellLat() { return cellLat; }
    public void setCellLat(double cellLat) { this.cellLat = cellLat; }

    public double getCellLng() { return cellLng; }
    public void setCellLng(double cellLng) { this.cellLng = cellLng; }

    public String getState() { return state; }
    public void setState(String state) { this.state = state; }

    public String getLga() { return lga; }
    public void setLga(String lga) { this.lga = lga; }

    public double getRiskScore() { return riskScore; }
    public void setRiskScore(double riskScore) { this.riskScore = riskScore; }

    public String getAlertLevel() { return alertLevel; }
    public void setAlertLevel(String alertLevel) { this.alertLevel = alertLevel; }

    public double getExpectedCount24h() { return expectedCount24h; }
    public void setExpectedCount24h(double expectedCount24h) { this.expectedCount24h = expectedCount24h; }

    public String getTrendDirection() { return trendDirection; }
    public void setTrendDirection(String trendDirection) { this.trendDirection = trendDirection; }

    public String getPeakTime() { return peakTime; }
    public void setPeakTime(String peakTime) { this.peakTime = peakTime; }

    public String getContributingFactors() { return contributingFactors; }
    public void setContributingFactors(String contributingFactors) { this.contributingFactors = contributingFactors; }

    public LocalDateTime getForecastTime() { return forecastTime; }
    public void setForecastTime(LocalDateTime forecastTime) { this.forecastTime = forecastTime; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public String getModelVersion() { return modelVersion; }
    public void setModelVersion(String modelVersion) { this.modelVersion = modelVersion; }
}
