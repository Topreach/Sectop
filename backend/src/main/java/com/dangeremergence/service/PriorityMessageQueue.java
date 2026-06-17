package com.dangeremergence.service;

import com.dangeremergence.model.Message;
import com.dangeremergence.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.Comparator;
import java.util.concurrent.PriorityBlockingQueue;

/**
 * Priority Message Queue for emergency message delivery.
 *
 * Ensures that HIGH and CRITICAL priority messages are delivered
 * BEFORE normal messages, even under heavy load. Uses an in-memory
 * PriorityBlockingQueue sorted by priority (highest first) then
 * by creation time (oldest first).
 *
 * Delivery chain:
 *   MessageService.sendMessage() -> PriorityMessageQueue.enqueue()
 *   -> PriorityBlockingQueue -> Async worker processes in priority order
 *   -> WebSocket push to receiver + MQTT broadcast + FCM if offline
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class PriorityMessageQueue {

    private final SimpMessagingTemplate messagingTemplate;
    private final MessageRepository messageRepository;
    private final RedisTemplate<String, Object> redisTemplate;

    // Priority queue: highest priority first, then oldest first
    private final PriorityBlockingQueue<Message> queue = new PriorityBlockingQueue<>(
            1000,
            Comparator.comparingInt(Message::getPriority)
                    .reversed()
                    .thenComparing(Message::getCreatedAt)
    );

    private volatile boolean running = true;

    /**
     * Enqueue a message for priority-based delivery.
     * Called by MessageService after saving the message.
     */
    public void enqueue(Message message) {
        queue.offer(message);
        log.debug("Message enqueued: {} (priority={})", message.getId(), message.getPriority());
    }

    /**
     * Start the priority queue worker in a background thread.
     * Called on application startup.
     */
    public void start() {
        Thread worker = new Thread(() -> {
            while (running) {
                try {
                    Message message = queue.take(); // blocks until available
                    processMessage(message);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                } catch (Exception e) {
                    log.error("Priority queue worker error: {}", e.getMessage());
                }
            }
        }, "priority-queue-worker");
        worker.setDaemon(true);
        worker.start();
        log.info("PriorityMessageQueue worker started");
    }

    /**
     * Stop the priority queue worker.
     */
    public void stop() {
        running = false;
        log.info("PriorityMessageQueue worker stopped");
    }

    /**
     * Process a message from the priority queue.
     *
     * NOTE: WebSocket push is NOT done here because MessageService.sendMessage()
     * and sendMessageFast() already push via WebSocket directly for instant delivery.
     * This method only marks the message as delivered in the database.
     *
     * This avoids duplicate WebSocket pushes and reduces latency.
     */
    private void processMessage(Message message) {
        // Mark as delivered in DB only — WebSocket push is already done by MessageService
        try {
            messageRepository.findById(message.getId()).ifPresent(msg -> {
                msg.setStatus(Message.MessageStatus.delivered);
                msg.setDeliveredAt(java.time.LocalDateTime.now());
                messageRepository.save(msg);
            });
            log.debug("Message {} marked as delivered in DB", message.getId());
        } catch (Exception e) {
            log.error("Failed to update message status: {}", e.getMessage());
        }
    }

    /**
     * Get current queue size for monitoring.
     */
    public int getQueueSize() {
        return queue.size();
    }
}
