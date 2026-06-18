package com.dangeremergence.repository;

import com.dangeremergence.model.Zone;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface ZoneRepository extends JpaRepository<Zone, String> {

    List<Zone> findByType(String type);

    List<Zone> findByStatus(Zone.ZoneStatus status);

    @Query("SELECT z FROM Zone z WHERE z.type = :type AND z.status = :status")
    List<Zone> findByTypeAndStatus(@Param("type") String type, @Param("status") Zone.ZoneStatus status);

    @Query("SELECT z FROM Zone z WHERE z.type <> :type AND z.status = :status")
    List<Zone> findByTypeNotAndStatus(@Param("type") String type, @Param("status") Zone.ZoneStatus status);

    @Query("SELECT z FROM Zone z WHERE z.latitude BETWEEN :minLat AND :maxLat " +
           "AND z.longitude BETWEEN :minLon AND :maxLon " +
           "AND z.status = :status")
    List<Zone> findZonesInArea(@Param("minLat") double minLat,
                                @Param("maxLat") double maxLat,
                                @Param("minLon") double minLon,
                                @Param("maxLon") double maxLon,
                                @Param("status") Zone.ZoneStatus status);

    @Query("SELECT z FROM Zone z WHERE z.createdAt > :since AND z.status = :status")
    List<Zone> findZonesSince(@Param("since") LocalDateTime since,
                               @Param("status") Zone.ZoneStatus status);

    @Query("SELECT z FROM Zone z WHERE z.expiresAt IS NOT NULL AND z.expiresAt < :now AND z.status = :status")
    List<Zone> findExpiredZones(@Param("now") LocalDateTime now,
                                 @Param("status") Zone.ZoneStatus status);
}
