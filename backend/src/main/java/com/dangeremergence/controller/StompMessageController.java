package com.dangeremergence.controller;

import com.dangeremergence.model.Message;
import com.dangeremergence.service.MessageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.stereotype.Controller;

import java.util.Map;

/**
 * STOMP message controller for real-time message sending via WebSocket.
 *
 * Handles messages sent via STOMP SEND frames from the frontend WebSocket
 * connection. This is faster than HTTP POST because it reuses the existing
 * WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * Destination: /app/messages/send
 * Mapped from: SEND destination:/app/messages/send
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompMessageController {

    private final MessageService messageService;

    /**
     * Handle a message sent via STOMP SEND frame.
     * This is the fast path for message delivery — reuses the existing
     * WebSocket connection instead of opening a new HTTP connection.
     */
    @MessageMapping("/messages/send")
    public void handleMessageSend(@Payload Map<String, Object> payload,
                                   SimpMessageHeaderAccessor headerAccessor) {
        try {
            String senderId = (String) payload.get("sender_id");
            String receiverId = (String) payload.get("receiver_id");
            String content = (String) payload.get("content");
            String messageTypeStr = (String) payload.getOrDefault("message_type", "text");
            Number priorityNum = (Number) payload.getOrDefault("priority", 0);
            int priority = priorityNum != null ? priorityNum.intValue() : 0;
            Number latNum = (Number) payload.get("latitude");
            Number lngNum = (Number) payload.get("longitude");
            Double latitude = latNum != null ? latNum.doubleValue() : null;
            Double longitude = lngNum != null ? lngNum.doubleValue() : null;

            Message.MessageType messageType;
            try {
                messageType = Message.MessageType.valueOf(messageTypeStr);
            } catch (IllegalArgumentException e) {
                messageType = Message.MessageType.text;
            }

            // Delegate to MessageService (non-transactional fast path)
            messageService.sendMessageFast(
                    senderId, receiverId, content, messageType, priority, latitude, longitude
            );

            log.debug("STOMP message processed: sender={}, type={}", senderId, messageType);
        } catch (Exception e) {
            log.error("STOMP message handling failed: {}", e.getMessage());
        }
    }
}
