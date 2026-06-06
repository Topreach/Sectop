package com.dangeremergence.repository;

import com.dangeremergence.model.SOSAlert;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface SOSAlertRepository extends JpaRepository<SOSAlert, String> {

    List<SOSAlert> findByUserIdOrderByCreatedAtDesc(String userId);

    List<SOSAlert> findByStatusOrderByPriorityDescCreatedAtDesc(SOSAlert.AlertStatus status);

    @Query("SELECT a FROM SOSAlert a WHERE a.status = :status AND a.createdAt > :since ORDER BY a.priority DESC, a.createdAt DESC")
    List<SOSAlert> findActiveAlertsSince(@Param("status") SOSAlert.AlertStatus status,
                                          @Param("since") LocalDateTime since);

    @Query("SELECT a FROM SOSAlert a WHERE a.latitude BETWEEN :minLat AND :maxLat " +
           "AND a.longitude BETWEEN :minLon AND :maxLon " +
           "AND a.status = :status ORDER BY a.priority DESC")
    List<SOSAlert> findAlertsInArea(@Param("minLat") double minLat,
                                     @Param("maxLat") double maxLat,
                                     @Param("minLon") double minLon,
                                     @Param("maxLon") double maxLon,
                                     @Param("status") SOSAlert.AlertStatus status);

    @Query("SELECT a FROM SOSAlert a WHERE a.status = :status AND a.createdAt < :expiresBefore")
    List<SOSAlert> findExpiredAlerts(@Param("status") SOSAlert.AlertStatus status,
                                      @Param("expiresBefore") LocalDateTime expiresBefore);

    long countByStatus(SOSAlert.AlertStatus status);
}
