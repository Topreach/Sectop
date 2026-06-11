package com.dangeremergence.repository;

import com.dangeremergence.model.TipOff;
import com.dangeremergence.model.TipOff.TipStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface TipOffRepository extends JpaRepository<TipOff, String> {

    List<TipOff> findByStatusOrderByThreatScoreDesc(TipStatus status);

    @Query("SELECT t FROM TipOff t WHERE t.status IN :statuses ORDER BY t.threatScore DESC, t.createdAt DESC")
    List<TipOff> findByStatusesOrderByThreatScoreDesc(@Param("statuses") List<TipStatus> statuses);

    @Query("SELECT t FROM TipOff t WHERE t.state = :state AND t.status = :status ORDER BY t.threatScore DESC")
    List<TipOff> findByStateAndStatus(@Param("state") String state, @Param("status") TipStatus status);

    List<TipOff> findByThreatScoreGreaterThanEqual(int minScore);

    List<TipOff> findByCreatedAtAfterOrderByCreatedAtDesc(LocalDateTime since);

    long countByStatus(TipStatus status);

    @Query("SELECT AVG(t.threatScore) FROM TipOff t WHERE t.status = :status")
    Double averageThreatScore(@Param("status") TipStatus status);
}
