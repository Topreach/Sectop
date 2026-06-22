package com.dangeremergence.service;

import com.dangeremergence.model.Message;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.MessageRepository;
import com.dangeremergence.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("MessageService Unit Tests")
class MessageServiceTest {

    @Mock
    private MessageRepository messageRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private PriorityMessageQueue priorityMessageQueue;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @InjectMocks
    private MessageService messageService;

    @Captor
    private ArgumentCaptor<Message> messageCaptor;

    private User sender;
    private User receiver;
    private Message testMessage;
    private final String senderId = "sender-123";
    private final String receiverId = "receiver-456";
    private final String messageId = "msg-789";

    @BeforeEach
    void setUp() {
        sender = User.builder()
                .id(senderId)
                .name("Sender")
                .email("sender@example.com")
                .role(User.UserRole.citizen)
                .active(true)
                .build();

        receiver = User.builder()
                .id(receiverId)
                .name("Receiver")
                .email("receiver@example.com")
                .role(User.UserRole.responder)
                .active(true)
                .build();

        testMessage = Message.builder()
                .id(messageId)
                .sender(sender)
                .receiver(receiver)
                .content("Hello, this is a test message")
                .messageType(Message.MessageType.text)
                .priority(5)
                .status(Message.MessageStatus.pending)
                .syncState(Message.SyncState.pending)
                .latitude(null)
                .longitude(null)
                .createdAt(LocalDateTime.now())
                .build();
    }

    @Nested
    @DisplayName("sendMessage()")
    class SendMessage {

        @Test
        @DisplayName("should save message, enqueue, and push WebSocket for normal priority")
        void shouldSendMessageSuccessfully() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Message result = messageService.sendMessage(
                    senderId, receiverId, "Hello", Message.MessageType.text,
                    5, null, null);

            assertThat(result).isNotNull();
            assertThat(result.getSender().getId()).isEqualTo(senderId);
            assertThat(result.getReceiver().getId()).isEqualTo(receiverId);
            assertThat(result.getContent()).isEqualTo("Hello");
            assertThat(result.getMessageType()).isEqualTo(Message.MessageType.text);
            assertThat(result.getPriority()).isEqualTo(5);
            assertThat(result.getStatus()).isEqualTo(Message.MessageStatus.pending);
            assertThat(result.getSyncState()).isEqualTo(Message.SyncState.pending);

            verify(messageRepository).save(any(Message.class));
            verify(priorityMessageQueue).enqueue(any(Message.class));
            verify(messagingTemplate).convertAndSendToUser(receiverId, "/queue/messages", result);
            verify(messagingTemplate, never()).convertAndSend("/topic/messages/urgent", result);
        }

        @Test
        @DisplayName("should push to urgent topic for priority >= 8")
        void shouldPushToUrgentTopicForHighPriority() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Message result = messageService.sendMessage(
                    senderId, receiverId, "URGENT!", Message.MessageType.alert,
                    10, null, null);

            verify(messagingTemplate).convertAndSend("/topic/messages/urgent", result);
        }

        @Test
        @DisplayName("should allow null receiver for broadcast messages")
        void shouldAllowNullReceiver() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Message result = messageService.sendMessage(
                    senderId, null, "Broadcast", Message.MessageType.alert,
                    5, null, null);

            assertThat(result.getReceiver()).isNull();
            verify(messagingTemplate, never()).convertAndSendToUser(anyString(), anyString(), any());
        }

        @Test
        @DisplayName("should throw when sender not found")
        void shouldThrowWhenSenderNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> messageService.sendMessage(
                    "unknown", receiverId, "Hello", Message.MessageType.text, 5, null, null))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Sender not found");

            verify(messageRepository, never()).save(any());
        }

        @Test
        @DisplayName("should throw when receiver not found")
        void shouldThrowWhenReceiverNotFound() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> messageService.sendMessage(
                    senderId, "unknown", "Hello", Message.MessageType.text, 5, null, null))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Receiver not found");

            verify(messageRepository, never()).save(any());
        }

        @Test
        @DisplayName("should handle WebSocket push failure gracefully")
        void shouldHandleWebSocketFailure() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));
            doThrow(new RuntimeException("Broker unavailable"))
                    .when(messagingTemplate).convertAndSendToUser(receiverId, "/queue/messages", any());

            Message result = messageService.sendMessage(
                    senderId, receiverId, "Hello", Message.MessageType.text, 5, null, null);

            // Should still return the saved message
            assertThat(result).isNotNull();
            verify(priorityMessageQueue).enqueue(any(Message.class));
        }

        @Test
        @DisplayName("should handle urgent topic push failure gracefully")
        void shouldHandleUrgentTopicFailure() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));
            doThrow(new RuntimeException("Topic unavailable"))
                    .when(messagingTemplate).convertAndSend("/topic/messages/urgent", any(Object.class));

            Message result = messageService.sendMessage(
                    senderId, receiverId, "URGENT!", Message.MessageType.alert, 10, null, null);

            assertThat(result).isNotNull();
        }
    }

    @Nested
    @DisplayName("sendMessageFast()")
    class SendMessageFast {

        @Test
        @DisplayName("should push WebSocket first, then save to DB")
        void shouldPushWebSocketFirst() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            messageService.sendMessageFast(
                    senderId, receiverId, "Fast message", Message.MessageType.text, 5, null, null);

            // WebSocket push happens before DB save
            verify(messagingTemplate).convertAndSendToUser(receiverId, "/queue/messages", any(Message.class));
            verify(messageRepository).save(any(Message.class));
            verify(priorityMessageQueue).enqueue(any(Message.class));
        }

        @Test
        @DisplayName("should push to urgent topic for high priority")
        void shouldPushToUrgentTopic() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            messageService.sendMessageFast(
                    senderId, receiverId, "URGENT!", Message.MessageType.alert, 10, null, null);

            verify(messagingTemplate).convertAndSend("/topic/messages/urgent", any(Message.class));
        }

        @Test
        @DisplayName("should handle sender not found gracefully (no exception propagation)")
        void shouldHandleSenderNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            // Should not throw — method catches all exceptions
            messageService.sendMessageFast(
                    "unknown", receiverId, "Hello", Message.MessageType.text, 5, null, null);

            verify(messageRepository, never()).save(any());
        }

        @Test
        @DisplayName("should handle receiver not found gracefully")
        void shouldHandleReceiverNotFound() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            messageService.sendMessageFast(
                    senderId, "unknown", "Hello", Message.MessageType.text, 5, null, null);

            verify(messageRepository, never()).save(any());
        }

        @Test
        @DisplayName("should handle WebSocket failure gracefully and still save")
        void shouldHandleWebSocketFailure() {
            when(userRepository.findById(senderId)).thenReturn(Optional.of(sender));
            when(userRepository.findById(receiverId)).thenReturn(Optional.of(receiver));
            doThrow(new RuntimeException("Broker down"))
                    .when(messagingTemplate).convertAndSendToUser(receiverId, "/queue/messages", any());
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            messageService.sendMessageFast(
                    senderId, receiverId, "Hello", Message.MessageType.text, 5, null, null);

            // Should still save to DB even if WebSocket fails
            verify(messageRepository).save(any(Message.class));
            verify(priorityMessageQueue).enqueue(any(Message.class));
        }
    }

    @Nested
    @DisplayName("markAsDelivered()")
    class MarkAsDelivered {

        @Test
        @DisplayName("should set status to delivered and record timestamp")
        void shouldMarkAsDelivered() {
            when(messageRepository.findById(messageId)).thenReturn(Optional.of(testMessage));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Message result = messageService.markAsDelivered(messageId);

            assertThat(result.getStatus()).isEqualTo(Message.MessageStatus.delivered);
            assertThat(result.getDeliveredAt()).isNotNull();
        }

        @Test
        @DisplayName("should throw when message not found")
        void shouldThrowWhenNotFound() {
            when(messageRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> messageService.markAsDelivered("unknown"))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Message not found");
        }
    }

    @Nested
    @DisplayName("markAsRead()")
    class MarkAsRead {

        @Test
        @DisplayName("should set status to read and record timestamp")
        void shouldMarkAsRead() {
            when(messageRepository.findById(messageId)).thenReturn(Optional.of(testMessage));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Message result = messageService.markAsRead(messageId);

            assertThat(result.getStatus()).isEqualTo(Message.MessageStatus.read);
            assertThat(result.getReadAt()).isNotNull();
        }

        @Test
        @DisplayName("should throw when message not found")
        void shouldThrowWhenNotFound() {
            when(messageRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> messageService.markAsRead("unknown"))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Message not found");
        }
    }

    @Nested
    @DisplayName("getMessagesForUser()")
    class GetMessagesForUser {

        @Test
        @DisplayName("should return messages for user")
        void shouldReturnMessages() {
            when(messageRepository.findMessagesForUser(senderId)).thenReturn(List.of(testMessage));

            List<Message> result = messageService.getMessagesForUser(senderId);

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getId()).isEqualTo(messageId);
        }

        @Test
        @DisplayName("should return empty list when no messages")
        void shouldReturnEmptyWhenNone() {
            when(messageRepository.findMessagesForUser(senderId)).thenReturn(List.of());

            List<Message> result = messageService.getMessagesForUser(senderId);

            assertThat(result).isEmpty();
        }
    }

    @Nested
    @DisplayName("getMessagesSince()")
    class GetMessagesSince {

        @Test
        @DisplayName("should return messages since given time")
        void shouldReturnMessagesSince() {
            LocalDateTime since = LocalDateTime.now().minusHours(1);
            when(messageRepository.findMessagesSince(senderId, since)).thenReturn(List.of(testMessage));

            List<Message> result = messageService.getMessagesSince(senderId, since);

            assertThat(result).hasSize(1);
        }
    }

    @Nested
    @DisplayName("getPendingSyncMessages()")
    class GetPendingSyncMessages {

        @Test
        @DisplayName("should return messages with pending sync state")
        void shouldReturnPendingSyncMessages() {
            when(messageRepository.findBySyncState(Message.SyncState.pending))
                    .thenReturn(List.of(testMessage));

            List<Message> result = messageService.getPendingSyncMessages();

            assertThat(result).hasSize(1);
        }
    }

    @Nested
    @DisplayName("markAsSynced()")
    class MarkAsSynced {

        @Test
        @DisplayName("should set sync state to synced when message exists")
        void shouldMarkAsSynced() {
            when(messageRepository.findById(messageId)).thenReturn(Optional.of(testMessage));
            when(messageRepository.save(any(Message.class))).thenAnswer(invocation -> invocation.getArgument(0));

            messageService.markAsSynced(messageId);

            verify(messageRepository).save(messageCaptor.capture());
            assertThat(messageCaptor.getValue().getSyncState()).isEqualTo(Message.SyncState.synced);
        }

        @Test
        @DisplayName("should do nothing when message not found")
        void shouldDoNothingWhenNotFound() {
            when(messageRepository.findById("unknown")).thenReturn(Optional.empty());

            messageService.markAsSynced("unknown");

            verify(messageRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("getUnreadCount()")
    class GetUnreadCount {

        @Test
        @DisplayName("should count delivered messages as unread")
        void shouldCountDeliveredMessages() {
            Message delivered = Message.builder()
                    .id("delivered-1")
                    .sender(sender)
                    .receiver(receiver)
                    .content("Delivered message")
                    .status(Message.MessageStatus.delivered)
                    .build();

            Message read = Message.builder()
                    .id("read-1")
                    .sender(sender)
                    .receiver(receiver)
                    .content("Read message")
                    .status(Message.MessageStatus.read)
                    .build();

            when(messageRepository.findMessagesForUser(receiverId))
                    .thenReturn(List.of(delivered, read));

            long count = messageService.getUnreadCount(receiverId);

            assertThat(count).isEqualTo(1);
        }

        @Test
        @DisplayName("should return 0 when no delivered messages")
        void shouldReturnZeroWhenNoneUnread() {
            Message read = Message.builder()
                    .id("read-1")
                    .sender(sender)
                    .receiver(receiver)
                    .content("Read message")
                    .status(Message.MessageStatus.read)
                    .build();

            when(messageRepository.findMessagesForUser(receiverId))
                    .thenReturn(List.of(read));

            long count = messageService.getUnreadCount(receiverId);

            assertThat(count).isEqualTo(0);
        }
    }

    @Nested
    @DisplayName("cleanupExpiredMessages()")
    class CleanupExpiredMessages {

        @Test
        @DisplayName("should delete messages older than 48h with pending status")
        void shouldDeleteExpiredMessages() {
            Message expired = Message.builder()
                    .id("expired-msg")
                    .sender(sender)
                    .receiver(receiver)
                    .content("Old message")
                    .status(Message.MessageStatus.pending)
                    .build();

            when(messageRepository.findExpiredMessages(eq(Message.MessageStatus.pending), any(LocalDateTime.class)))
                    .thenReturn(List.of(expired));

            messageService.cleanupExpiredMessages();

            verify(messageRepository).deleteAll(List.of(expired));
        }

        @Test
        @DisplayName("should do nothing when no expired messages")
        void shouldDoNothingWhenNoneExpired() {
            when(messageRepository.findExpiredMessages(eq(Message.MessageStatus.pending), any(LocalDateTime.class)))
                    .thenReturn(List.of());

            messageService.cleanupExpiredMessages();

            verify(messageRepository, never()).deleteAll(any());
        }
    }
}