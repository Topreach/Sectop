package com.dangeremergence.service;

import com.dangeremergence.model.Broadcast;
import com.dangeremergence.model.Broadcast.BroadcastSeverity;
import com.dangeremergence.model.Broadcast.BroadcastType;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.BroadcastRepository;
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
@DisplayName("BroadcastService Unit Tests")
class BroadcastServiceTest {

    @Mock
    private BroadcastRepository broadcastRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private MqttService mqttService;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @InjectMocks
    private BroadcastService broadcastService;

    @Captor
    private ArgumentCaptor<Broadcast> broadcastCaptor;

    private User testUser;
    private Broadcast testBroadcast;
    private final String userId = "user-123";
    private final String broadcastId = "broadcast-456";

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .id(userId)
                .name("Admin User")
                .email("admin@example.com")
                .role(User.UserRole.coordinator)
                .active(true)
                .build();

        testBroadcast = Broadcast.builder()
                .id(broadcastId)
                .title("Emergency Alert")
                .message("Flood warning in Ikeja area")
                .severity(BroadcastSeverity.warning)
                .broadcastType(BroadcastType.general)
                .targetState("Lagos")
                .targetLga("Ikeja")
                .isActive(true)
                .createdBy(testUser)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
    }

    @Nested
    @DisplayName("createBroadcast()")
    class CreateBroadcast {

        @Test
        @DisplayName("should create broadcast with valid inputs")
        void shouldCreateBroadcast() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Broadcast result = broadcastService.createBroadcast(
                    "Emergency Alert", "Flood warning", "warning", "general",
                    "Lagos", "Ikeja", "citizen,responder",
                    6.5244, 3.3792, 50.0, userId, LocalDateTime.now().plusHours(24));

            assertThat(result.getTitle()).isEqualTo("Emergency Alert");
            assertThat(result.getMessage()).isEqualTo("Flood warning");
            assertThat(result.getSeverity()).isEqualTo(BroadcastSeverity.warning);
            assertThat(result.getBroadcastType()).isEqualTo(BroadcastType.general);
            assertThat(result.isActive()).isTrue();
            assertThat(result.getCreatedBy().getId()).isEqualTo(userId);

            verify(mqttService).publish(eq("broadcasts/new"), any(Broadcast.class));
            verify(mqttService).publish(eq("broadcasts/state/lagos"), any(Broadcast.class));
            verify(mqttService).publish(eq("broadcasts/lga/ikeja"), any(Broadcast.class));
            verify(messagingTemplate).convertAndSend(eq("/topic/broadcasts"), anyMap());
        }

        @Test
        @DisplayName("should throw when title is null or empty")
        void shouldThrowWhenTitleMissing() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    null, "message", "warning", "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Title is required");

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "   ", "message", "warning", "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Title is required");
        }

        @Test
        @DisplayName("should throw when title exceeds 200 characters")
        void shouldThrowWhenTitleTooLong() {
            String longTitle = "a".repeat(201);

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    longTitle, "message", "warning", "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Title must be 200 characters or less");
        }

        @Test
        @DisplayName("should throw when message is null or empty")
        void shouldThrowWhenMessageMissing() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", null, "warning", "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Message is required");
        }

        @Test
        @DisplayName("should throw when message exceeds 5000 characters")
        void shouldThrowWhenMessageTooLong() {
            String longMsg = "a".repeat(5001);

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", longMsg, "warning", "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Message must be 5000 characters or less");
        }

        @Test
        @DisplayName("should throw when severity is invalid")
        void shouldThrowWhenInvalidSeverity() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", null, "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Severity is required");

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "invalid", "general", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid severity");
        }

        @Test
        @DisplayName("should throw when broadcast type is invalid")
        void shouldThrowWhenInvalidType() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", null, null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Broadcast type is required");

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "invalid_type", null, null, null,
                    null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid broadcast type");
        }

        @Test
        @DisplayName("should throw when latitude is out of range")
        void shouldThrowWhenInvalidLatitude() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    91.0, 3.4, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid latitude");

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    -91.0, 3.4, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid latitude");
        }

        @Test
        @DisplayName("should throw when longitude is out of range")
        void shouldThrowWhenInvalidLongitude() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    6.5, 181.0, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid longitude");

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    6.5, -181.0, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid longitude");
        }

        @Test
        @DisplayName("should throw when radius is out of range")
        void shouldThrowWhenInvalidRadius() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    null, null, -1.0, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Radius must be between 0 and 1000 km");

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    null, null, 1001.0, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Radius must be between 0 and 1000 km");
        }

        @Test
        @DisplayName("should throw when expiration is in the past")
        void shouldThrowWhenExpirationInPast() {
            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    null, null, null, userId, LocalDateTime.now().minusHours(1)))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Expiration time must be in the future");
        }

        @Test
        @DisplayName("should handle null creator gracefully")
        void shouldHandleNullCreator() {
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Broadcast result = broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    null, null, null, null, null);

            assertThat(result.getCreatedBy()).isNull();
            assertThat(result.getTitle()).isEqualTo("Title");
        }

        @Test
        @DisplayName("should handle MQTT publish failure gracefully")
        void shouldHandleMqttFailure() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));
            doThrow(new RuntimeException("MQTT broker unavailable"))
                    .when(mqttService).publish(anyString(), any());

            Broadcast result = broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", "Lagos", "Ikeja", null,
                    null, null, null, userId, null);

            // Should still return the broadcast even if MQTT fails
            assertThat(result).isNotNull();
            // WebSocket should still be attempted
            verify(messagingTemplate).convertAndSend(eq("/topic/broadcasts"), anyMap());
        }

        @Test
        @DisplayName("should handle WebSocket publish failure gracefully")
        void shouldHandleWebSocketFailure() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));
            doThrow(new RuntimeException("WebSocket unavailable"))
                    .when(messagingTemplate).convertAndSend(anyString(), any());

            Broadcast result = broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general", null, null, null,
                    null, null, null, userId, null);

            assertThat(result).isNotNull();
        }

        @Test
        @DisplayName("should trim whitespace from title and message")
        void shouldTrimWhitespace() {
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Broadcast result = broadcastService.createBroadcast(
                    "  Title with spaces  ", "  Message with spaces  ", "warning", "general",
                    null, null, null, null, null, null, null, null);

            assertThat(result.getTitle()).isEqualTo("Title with spaces");
            assertThat(result.getMessage()).isEqualTo("Message with spaces");
        }

        @Test
        @DisplayName("should normalize empty target state/LGA to null")
        void shouldNormalizeEmptyTargets() {
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));

            Broadcast result = broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general",
                    "   ", "   ", null, null, null, null, null, null);

            assertThat(result.getTargetState()).isNull();
            assertThat(result.getTargetLga()).isNull();
        }

        @Test
        @DisplayName("should throw when target state name is too long")
        void shouldThrowWhenTargetStateTooLong() {
            String longState = "a".repeat(101);

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general",
                    longState, null, null, null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Target state name is too long");
        }

        @Test
        @DisplayName("should throw when target LGA name is too long")
        void shouldThrowWhenTargetLgaTooLong() {
            String longLga = "a".repeat(101);

            assertThatThrownBy(() -> broadcastService.createBroadcast(
                    "Title", "Message", "warning", "general",
                    null, longLga, null, null, null, null, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Target LGA name is too long");
        }
    }

    @Nested
    @DisplayName("getActiveBroadcasts()")
    class GetActiveBroadcasts {

        @Test
        @DisplayName("should return all active broadcasts when no location filter")
        void shouldReturnAllActive() {
            when(broadcastRepository.findAllActiveBroadcasts(any(LocalDateTime.class)))
                    .thenReturn(List.of(testBroadcast));

            List<Broadcast> result = broadcastService.getActiveBroadcasts(null, null);

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getId()).isEqualTo(broadcastId);
        }

        @Test
        @DisplayName("should filter by state when provided")
        void shouldFilterByState() {
            when(broadcastRepository.findActiveBroadcastsForLocation(eq("Lagos"), isNull(), any(LocalDateTime.class)))
                    .thenReturn(List.of(testBroadcast));

            List<Broadcast> result = broadcastService.getActiveBroadcasts("Lagos", null);

            assertThat(result).hasSize(1);
        }

        @Test
        @DisplayName("should filter by state and LGA when both provided")
        void shouldFilterByStateAndLga() {
            when(broadcastRepository.findActiveBroadcastsForLocation(eq("Lagos"), eq("Ikeja"), any(LocalDateTime.class)))
                    .thenReturn(List.of(testBroadcast));

            List<Broadcast> result = broadcastService.getActiveBroadcasts("Lagos", "Ikeja");

            assertThat(result).hasSize(1);
        }
    }

    @Nested
    @DisplayName("getBroadcastById()")
    class GetBroadcastById {

        @Test
        @DisplayName("should return broadcast when found")
        void shouldReturnBroadcast() {
            when(broadcastRepository.findById(broadcastId)).thenReturn(Optional.of(testBroadcast));

            Optional<Broadcast> result = broadcastService.getBroadcastById(broadcastId);

            assertThat(result).isPresent();
            assertThat(result.get().getId()).isEqualTo(broadcastId);
        }

        @Test
        @DisplayName("should return empty when not found")
        void shouldReturnEmptyWhenNotFound() {
            when(broadcastRepository.findById("unknown")).thenReturn(Optional.empty());

            Optional<Broadcast> result = broadcastService.getBroadcastById("unknown");

            assertThat(result).isEmpty();
        }
    }

    @Nested
    @DisplayName("expireBroadcast()")
    class ExpireBroadcast {

        @Test
        @DisplayName("should set active to false when broadcast exists")
        void shouldExpireBroadcast() {
            when(broadcastRepository.findById(broadcastId)).thenReturn(Optional.of(testBroadcast));
            when(broadcastRepository.save(any(Broadcast.class))).thenAnswer(invocation -> invocation.getArgument(0));

            broadcastService.expireBroadcast(broadcastId);

            verify(broadcastRepository).save(broadcastCaptor.capture());
            assertThat(broadcastCaptor.getValue().isActive()).isFalse();
            assertThat(broadcastCaptor.getValue().getUpdatedAt()).isNotNull();
        }

        @Test
        @DisplayName("should do nothing when broadcast not found")
        void shouldDoNothingWhenNotFound() {
            when(broadcastRepository.findById("unknown")).thenReturn(Optional.empty());

            broadcastService.expireBroadcast("unknown");

            verify(broadcastRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("getActiveBroadcastCount()")
    class GetActiveBroadcastCount {

        @Test
        @DisplayName("should return count of active broadcasts")
        void shouldReturnCount() {
            when(broadcastRepository.countByIsActiveTrue()).thenReturn(3L);

            long count = broadcastService.getActiveBroadcastCount();

            assertThat(count).isEqualTo(3L);
        }
    }
}