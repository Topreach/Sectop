package com.dangeremergence.service;

import com.dangeremergence.model.Message;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.MessageRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class MessageService {

    private final MessageRepository messageRepository;
    private final UserRepository userRepository;
    private final PriorityMessageQueue priorityMessageQueue;
    private final SimpMessagingTemplate messagingTemplate;

    @Transactional
    public Message sendMessage(String senderId, String receiverId, String content,
                                Message.MessageType type, int priority, Double latitude, Double longitude) {
        User sender = userRepository.findById(senderId)
                .orElseThrow(() -> new RuntimeException("Sender not found: " + senderId));

        User receiver = null;
        if (receiverId != null) {
            receiver = userRepository.findById(receiverId)
                    .orElseThrow(() -> new RuntimeException("Receiver not found: " + receiverId));
        }

        Message message = Message.builder()
                .id(UUID.randomUUID().toString())
                .sender(sender)
                .receiver(receiver)
                .content(content)
                .messageType(type)
                .priority(priority)
                .status(Message.MessageStatus.pending)
                .syncState(Message.SyncState.pending)
                .latitude(latitude)
                .longitude(longitude)
                .createdAt(LocalDateTime.now())
                .build();

        Message saved = messageRepository.save(message);
        log.info("Message saved: {} (type={}, priority={})", saved.getId(), type, priority);

        // Enqueue in priority message queue for instant delivery
        priorityMessageQueue.enqueue(saved);

        // Also push directly via WebSocket for immediate delivery to connected clients
        if (receiver != null) {
            try {
                messagingTemplate.convertAndSendToUser(receiver.getId(), "/queue/messages", saved);
                log.debug("Direct WebSocket push for message {} to user {}", saved.getId(), receiver.getId());
            } catch (Exception e) {
                log.warn("Direct WebSocket push failed for message {}: {}", saved.getId(), e.getMessage());
            }
        }

        // For high-priority messages, also push to global urgent topic
        if (priority >= 8) {
            try {
                messagingTemplate.convertAndSend("/topic/messages/urgent", saved);
            } catch (Exception e) {
                log.warn("Global urgent topic push failed: {}", e.getMessage());
            }
        }

        return saved;
    }

    @Transactional
    public Message markAsDelivered(String messageId) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new RuntimeException("Message not found: " + messageId));
        message.setStatus(Message.MessageStatus.delivered);
        message.setDeliveredAt(LocalDateTime.now());
        return messageRepository.save(message);
    }

    @Transactional
    public Message markAsRead(String messageId) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new RuntimeException("Message not found: " + messageId));
        message.setStatus(Message.MessageStatus.read);
        message.setReadAt(LocalDateTime.now());
        return messageRepository.save(message);
    }

    @Transactional(readOnly = true)
    public List<Message> getMessagesForUser(String userId) {
        return messageRepository.findMessagesForUser(userId);
    }

    @Transactional(readOnly = true)
    public List<Message> getMessagesSince(String userId, LocalDateTime since) {
        return messageRepository.findMessagesSince(userId, since);
    }

    @Transactional(readOnly = true)
    public List<Message> getPendingSyncMessages() {
        return messageRepository.findBySyncState(Message.SyncState.pending);
    }

    @Transactional
    public void markAsSynced(String messageId) {
        messageRepository.findById(messageId).ifPresent(message -> {
            message.setSyncState(Message.SyncState.synced);
            messageRepository.save(message);
        });
    }

    @Transactional
    @Async
    public void processIncomingMessage(Message message) {
        // Trigger AI prioritization via FastAPI
        // Send push notification to receiver
        // Broadcast to mesh network if needed
        log.info("Processing incoming message: {}", message.getId());
    }

    @Transactional(readOnly = true)
    public long getUnreadCount(String userId) {
        return messageRepository.findMessagesForUser(userId).stream()
                .filter(m -> m.getStatus() == Message.MessageStatus.delivered)
                .count();
    }

    @Transactional
    public void cleanupExpiredMessages() {
        LocalDateTime expiryThreshold = LocalDateTime.now().minusHours(48);
        List<Message> expired = messageRepository.findExpiredMessages(
                Message.MessageStatus.pending, expiryThreshold);
        messageRepository.deleteAll(expired);
        log.info("Cleaned up {} expired messages", expired.size());
    }
}
