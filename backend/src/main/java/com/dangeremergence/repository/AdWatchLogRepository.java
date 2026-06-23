package com.dangeremergence.repository;

import com.dangeremergence.model.AdWatchLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;

@Repository
public interface AdWatchLogRepository extends JpaRepository<AdWatchLog, String> {
    int countByUserIdAndWatchedAtAfter(String userId, LocalDateTime after);
}
