package com.dangeremergence.repository;

import com.dangeremergence.model.Broadcast;
import com.dangeremergence.model.Broadcast.BroadcastSeverity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface BroadcastRepository extends JpaRepository<Broadcast, String> {

    List<Broadcast> findByIsActiveTrueOrderByCreatedAtDesc();

    List<Broadcast> findBySeverityAndIsActiveTrueOrderByCreatedAtDesc(BroadcastSeverity severity);

    @Query("SELECT b FROM Broadcast b WHERE b.isActive = true " +
           "AND (b.expiresAt IS NULL OR b.expiresAt > :now) " +
           "AND (:state IS NULL OR b.targetState IS NULL OR b.targetState = :state) " +
           "AND (:lga IS NULL OR b.targetLga IS NULL OR b.targetLga = :lga) " +
           "ORDER BY b.severity DESC, b.createdAt DESC")
    List<Broadcast> findActiveBroadcastsForLocation(
            @Param("state") String state,
            @Param("lga") String lga,
            @Param("now") LocalDateTime now);

    @Query("SELECT b FROM Broadcast b WHERE b.isActive = true " +
           "AND (b.expiresAt IS NULL OR b.expiresAt > :now) " +
           "ORDER BY b.severity DESC, b.createdAt DESC")
    List<Broadcast> findAllActiveBroadcasts(@Param("now") LocalDateTime now);

    long countByIsActiveTrue();
}
