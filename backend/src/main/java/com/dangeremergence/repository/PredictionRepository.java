package com.dangeremergence.repository;

import com.dangeremergence.model.Prediction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

/**
 * JPA repository for Prediction entities.
 *
 * Provides queries for retrieving predictions by grid cell,
 * time range, risk score threshold, and geographic area.
 */
@Repository
public interface PredictionRepository extends JpaRepository<Prediction, String> {

    /** Find predictions for a specific grid cell, ordered by forecast time descending. */
    List<Prediction> findByCellLatAndCellLngOrderByForecastTimeDesc(double cellLat, double cellLng);

    /** Find predictions within a geographic bounding box. */
    @Query("SELECT p FROM Prediction p WHERE p.cellLat BETWEEN :minLat AND :maxLat " +
           "AND p.cellLng BETWEEN :minLng AND :maxLng " +
           "ORDER BY p.riskScore DESC")
    List<Prediction> findPredictionsInArea(
            @Param("minLat") double minLat,
            @Param("maxLat") double maxLat,
            @Param("minLng") double minLng,
            @Param("maxLng") double maxLng);

    /** Find predictions for a specific state, ordered by risk score descending. */
    List<Prediction> findByStateOrderByRiskScoreDesc(String state);

    /** Find predictions with risk score above a threshold. */
    List<Prediction> findByRiskScoreGreaterThanEqualOrderByRiskScoreDesc(double minRiskScore);

    /** Find predictions created after a specific time. */
    List<Prediction> findByCreatedAtAfterOrderByRiskScoreDesc(LocalDateTime since);

    /** Find predictions for a forecast time window. */
    @Query("SELECT p FROM Prediction p WHERE p.forecastTime BETWEEN :start AND :end " +
           "ORDER BY p.riskScore DESC")
    List<Prediction> findPredictionsInTimeWindow(
            @Param("start") LocalDateTime start,
            @Param("end") LocalDateTime end);

    /** Find the most recent predictions (latest first). */
    List<Prediction> findTop50ByOrderByCreatedAtDesc();

    /** Count predictions with a specific alert level. */
    long countByAlertLevel(String alertLevel);

    /** Delete predictions older than a given time. */
    void deleteByCreatedAtBefore(LocalDateTime cutoff);
}
