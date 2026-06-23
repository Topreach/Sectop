package com.dangeremergence.repository;

import com.dangeremergence.model.PointTransaction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface PointTransactionRepository extends JpaRepository<PointTransaction, String> {
    List<PointTransaction> findByUserIdOrderByCreatedAtDesc(String userId);

    int countByUserIdAndTransactionTypeAndCreatedAtAfter(
            String userId, String transactionType, LocalDateTime after);
}
