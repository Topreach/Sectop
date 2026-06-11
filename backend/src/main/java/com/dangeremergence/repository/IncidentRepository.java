package com.dangeremergence.repository;

import com.dangeremergence.model.Incident;
import com.dangeremergence.model.Incident.IncidentSeverity;
import com.dangeremergence.model.Incident.IncidentStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface IncidentRepository extends JpaRepository<Incident, String> {

    List<Incident> findByReporterIdOrderByCreatedAtDesc(String reporterId);

    List<Incident> findByStatusOrderByCreatedAtDesc(IncidentStatus status);

    List<Incident> findByIncidentTypeAndStatusOrderByOccurredAtDesc(
            String incidentType, IncidentStatus status);

    @Query("SELECT i FROM Incident i WHERE i.status = :status " +
           "AND i.occurredAt > :since ORDER BY i.severity DESC, i.occurredAt DESC")
    List<Incident> findRecentIncidents(@Param("status") IncidentStatus status,
                                        @Param("since") LocalDateTime since);

    @Query("SELECT i FROM Incident i WHERE i.latitude BETWEEN :minLat AND :maxLat " +
           "AND i.longitude BETWEEN :minLon AND :maxLon " +
           "AND i.status = :status ORDER BY i.severity DESC, i.occurredAt DESC")
    List<Incident> findIncidentsInArea(@Param("minLat") double minLat,
                                        @Param("maxLat") double maxLat,
                                        @Param("minLon") double minLon,
                                        @Param("maxLon") double maxLon,
                                        @Param("status") IncidentStatus status);

    @Query("SELECT i FROM Incident i WHERE i.latitude BETWEEN :minLat AND :maxLat " +
           "AND i.longitude BETWEEN :minLon AND :maxLon " +
           "AND i.status = :status " +
           "AND i.incidentType IN :types " +
           "ORDER BY i.severity DESC, i.occurredAt DESC")
    List<Incident> findIncidentsInAreaByType(@Param("minLat") double minLat,
                                              @Param("maxLat") double maxLat,
                                              @Param("minLon") double minLon,
                                              @Param("maxLon") double maxLon,
                                              @Param("status") IncidentStatus status,
                                              @Param("types") List<String> types);

    @Query("SELECT i FROM Incident i WHERE i.state = :state " +
           "AND i.status = :status ORDER BY i.occurredAt DESC")
    List<Incident> findByState(@Param("state") String state,
                                @Param("status") IncidentStatus status);

    @Query("SELECT i FROM Incident i WHERE i.lga = :lga " +
           "AND i.state = :state " +
           "AND i.status = :status ORDER BY i.occurredAt DESC")
    List<Incident> findByLgaAndState(@Param("lga") String lga,
                                      @Param("state") String state,
                                      @Param("status") IncidentStatus status);

    @Query("SELECT i.severity, COUNT(i) FROM Incident i " +
           "WHERE i.status = :status GROUP BY i.severity")
    List<Object[]> countBySeverity(@Param("status") IncidentStatus status);

    @Query("SELECT i.incidentType, COUNT(i) FROM Incident i " +
           "WHERE i.status = :status GROUP BY i.incidentType ORDER BY COUNT(i) DESC")
    List<Object[]> countByType(@Param("status") IncidentStatus status);

    long countByStatus(IncidentStatus status);

    @Query("SELECT COUNT(i) FROM Incident i WHERE i.status = :status " +
           "AND i.severity = :severity")
    long countByStatusAndSeverity(@Param("status") IncidentStatus status,
                                   @Param("severity") IncidentSeverity severity);

    @Query("SELECT i FROM Incident i WHERE i.occurredAt > :since " +
           "AND i.status = :status ORDER BY i.occurredAt DESC")
    List<Incident> findIncidentsSince(@Param("since") LocalDateTime since,
                                       @Param("status") IncidentStatus status);
}
