package com.dangeremergence.repository;

import com.dangeremergence.model.Message;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface MessageRepository extends JpaRepository<Message, String> {

    List<Message> findBySenderIdOrderByCreatedAtDesc(String senderId);

    List<Message> findByReceiverIdOrderByCreatedAtDesc(String receiverId);

    @Query("SELECT m FROM Message m WHERE m.sender.id = :userId OR m.receiver.id = :userId ORDER BY m.createdAt DESC")
    List<Message> findMessagesForUser(@Param("userId") String userId);

    @Query("SELECT m FROM Message m WHERE m.createdAt > :since AND (m.sender.id = :userId OR m.receiver.id = :userId)")
    List<Message> findMessagesSince(@Param("userId") String userId, @Param("since") LocalDateTime since);

    @Query("SELECT m FROM Message m WHERE m.syncState = :state ORDER BY m.createdAt ASC")
    List<Message> findBySyncState(@Param("state") Message.SyncState state);

    @Query("SELECT m FROM Message m WHERE m.status = :status AND m.createdAt < :expiresBefore")
    List<Message> findExpiredMessages(@Param("status") Message.MessageStatus status,
                                       @Param("expiresBefore") LocalDateTime expiresBefore);

    List<Message> findByPriorityGreaterThanEqual(int minPriority);

    long countByStatus(Message.MessageStatus status);
}
