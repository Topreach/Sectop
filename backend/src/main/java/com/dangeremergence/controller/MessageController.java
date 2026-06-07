package com.dangeremergence.controller;

import com.dangeremergence.model.Message;
import com.dangeremergence.service.MessageService;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/messages")
@RequiredArgsConstructor
public class MessageController {

    private final MessageService messageService;

    @PostMapping
    public ResponseEntity<Message> sendMessage(@RequestBody Map<String, Object> request) {
        Number priorityNumber = (Number) request.getOrDefault("priority", 0);
        int priority = priorityNumber != null ? priorityNumber.intValue() : 0;

        Message message = messageService.sendMessage(
                (String) request.get("sender_id"),
                (String) request.get("receiver_id"),
                (String) request.get("content"),
                Message.MessageType.valueOf((String) request.getOrDefault("message_type", "text")),
                priority,
                request.get("latitude") != null ? ((Number) request.get("latitude")).doubleValue() : null,
                request.get("longitude") != null ? ((Number) request.get("longitude")).doubleValue() : null
        );
        return ResponseEntity.ok(message);
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<List<Message>> getMessagesForUser(@PathVariable String userId) {
        return ResponseEntity.ok(messageService.getMessagesForUser(userId));
    }

    @GetMapping("/sync")
    public ResponseEntity<List<Message>> getMessagesSince(
            @RequestParam String userId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime since) {
        return ResponseEntity.ok(messageService.getMessagesSince(userId, since));
    }

    @PutMapping("/{messageId}/deliver")
    public ResponseEntity<Message> markAsDelivered(@PathVariable String messageId) {
        return ResponseEntity.ok(messageService.markAsDelivered(messageId));
    }

    @PutMapping("/{messageId}/read")
    public ResponseEntity<Message> markAsRead(@PathVariable String messageId) {
        return ResponseEntity.ok(messageService.markAsRead(messageId));
    }

    @PutMapping("/{messageId}/sync")
    public ResponseEntity<Void> markAsSynced(@PathVariable String messageId) {
        messageService.markAsSynced(messageId);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/pending-sync")
    public ResponseEntity<List<Message>> getPendingSyncMessages() {
        return ResponseEntity.ok(messageService.getPendingSyncMessages());
    }

    @GetMapping("/unread/{userId}")
    public ResponseEntity<Map<String, Long>> getUnreadCount(@PathVariable String userId) {
        long count = messageService.getUnreadCount(userId);
        return ResponseEntity.ok(Map.of("count", count));
    }
}
