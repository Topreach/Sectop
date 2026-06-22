package com.dangeremergence.sos.repository;

import com.dangeremergence.sos.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Minimal User repository for the SOS microservice.
 * Only provides queries needed for SOS alert processing.
 */
@Repository
public interface UserRepository extends JpaRepository<User, String> {

    @Query("SELECT u FROM User u WHERE u.latitude BETWEEN :minLat AND :maxLat " +
           "AND u.longitude BETWEEN :minLon AND :maxLon " +
           "AND u.fcmToken IS NOT NULL AND u.fcmToken <> ''")
    List<User> findUsersInArea(@Param("minLat") double minLat,
                                @Param("maxLat") double maxLat,
                                @Param("minLon") double minLon,
                                @Param("maxLon") double maxLon);

    @Query("SELECT u FROM User u WHERE u.latitude BETWEEN :minLat AND :maxLat " +
           "AND u.longitude BETWEEN :minLon AND :maxLon " +
           "AND u.role IN ('responder', 'guardian', 'coordinator') " +
           "AND u.fcmToken IS NOT NULL AND u.fcmToken <> ''")
    List<User> findVerifiedRespondersInArea(@Param("minLat") double minLat,
                                             @Param("maxLat") double maxLat,
                                             @Param("minLon") double minLon,
                                             @Param("maxLon") double maxLon);

    @Query("SELECT u FROM User u WHERE u.id IN :ids")
    List<User> findUsersByIds(@Param("ids") List<String> ids);
}
