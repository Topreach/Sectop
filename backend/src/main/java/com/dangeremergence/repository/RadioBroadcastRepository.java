package com.dangeremergence.repository;

import com.dangeremergence.model.RadioBroadcast;
import com.dangeremergence.model.RadioBroadcast.BroadcastStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface RadioBroadcastRepository extends JpaRepository<RadioBroadcast, String> {

    List<RadioBroadcast> findByStatusOrderByCreatedAtDesc(BroadcastStatus status);

    @Query("SELECT r FROM RadioBroadcast r WHERE r.targetState = :state " +
           "AND r.status = :status ORDER BY r.createdAt DESC")
    List<RadioBroadcast> findByTargetStateAndStatus(
            @Param("state") String state,
            @Param("status") BroadcastStatus status);

    List<RadioBroadcast> findAllByOrderByCreatedAtDesc();

    long countByStatus(BroadcastStatus status);
}
