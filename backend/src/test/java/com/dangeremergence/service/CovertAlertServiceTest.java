package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.UserRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import java.time.LocalDateTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("CovertAlertService Unit Tests")
class CovertAlertServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private FcmPushService fcmPushService;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private ObjectMapper objectMapper;

    @InjectMocks
    private CovertAlertService covertAlertService;

    private User alertUser;
    private SOSAlert covertAlert;
    private final String userId = "victim-123";
    private final String alertId = "alert-456";

    @BeforeEach
    void setUp() {
        alertUser = User.builder()
                .id(userId)
                .name("Victim User")
                .email("victim@example.com")
                .phone("+2348012345678")
                .role(User.UserRole.citizen)
                .active(true)
                .emergencyContacts("[\"contact-1\", \"contact-2\"]")
                .build();

        covertAlert = SOSAlert.builder()
                .id(alertId)
                .user(alertUser)
                .alertType("fire")
                .description("Fire at market")
                .latitude(6.5244)
                .longitude(3.3792)
                .priority(10)
                .covert(true)
                .status(SOSAlert.AlertStatus.active)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
    }

    @Nested
    @DisplayName("processCovertAlert()")
    class ProcessCovertAlert {

        @Test
        @DisplayName("should notify emergency contacts and verified responders via FCM")
        void shouldNotifyContactsAndResponders() throws Exception {
            User contact = User.builder()
                    .id("contact-1")
                    .name("Emergency Contact")
                    .fcmToken("contact-fcm-token")
                    .build();

            User responder = User.builder()
                    .id("responder-1")
                    .name("Verified Responder")
                    .role(User.UserRole.responder)
                    .fcmToken("responder-fcm-token")
                    .build();

            when(objectMapper.readValue(eq("[\"contact-1\", \"contact-2\"]"), any(TypeReference.class)))
                    .thenReturn(List.of("contact-1", "contact-2"));
            when(userRepository.findUsersByIds(List.of("contact-1", "contact-2")))
                    .thenReturn(List.of(contact));
            when(userRepository.findVerifiedRespondersInArea(anyDouble(), anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of(responder));

            covertAlertService.processCovertAlert(covertAlert);

            // Should send FCM to contact (has token)
            verify(fcmPushService).sendCovertNotification(contact, covertAlert);
            // Should send FCM to responder (has token)
            verify(fcmPushService).sendCovertNotification(responder, covertAlert);
            // Should send WebSocket acknowledgment to victim
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);
        }

        @Test
        @DisplayName("should skip contacts without FCM token")
        void shouldSkipContactsWithoutToken() throws Exception {
            User contactNoToken = User.builder()
                    .id("contact-1")
                    .name("No Token Contact")
                    .fcmToken(null)
                    .build();

            when(objectMapper.readValue(eq("[\"contact-1\"]"), any(TypeReference.class)))
                    .thenReturn(List.of("contact-1"));
            when(userRepository.findUsersByIds(List.of("contact-1")))
                    .thenReturn(List.of(contactNoToken));
            when(userRepository.findVerifiedRespondersInArea(anyDouble(), anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());

            covertAlertService.processCovertAlert(covertAlert);

            verify(fcmPushService, never()).sendCovertNotification(contactNoToken, covertAlert);
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);
        }

        @Test
        @DisplayName("should handle empty emergency contacts gracefully")
        void shouldHandleEmptyContacts() throws Exception {
            alertUser.setEmergencyContacts("[]");

            when(objectMapper.readValue(eq("[]"), any(TypeReference.class)))
                    .thenReturn(List.of());
            when(userRepository.findVerifiedRespondersInArea(anyDouble(), anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());

            covertAlertService.processCovertAlert(covertAlert);

            verify(fcmPushService, never()).sendCovertNotification(any(), any());
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);
        }

        @Test
        @DisplayName("should handle null emergency contacts gracefully")
        void shouldHandleNullContacts() {
            alertUser.setEmergencyContacts(null);

            when(userRepository.findVerifiedRespondersInArea(anyDouble(), anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());

            covertAlertService.processCovertAlert(covertAlert);

            verify(fcmPushService, never()).sendCovertNotification(any(), any());
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);
        }

        @Test
        @DisplayName("should handle JSON parse failure gracefully")
        void shouldHandleJsonParseFailure() throws Exception {
            when(objectMapper.readValue(anyString(), any(TypeReference.class)))
                    .thenThrow(new RuntimeException("Invalid JSON"));
            when(userRepository.findVerifiedRespondersInArea(anyDouble(), anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());

            covertAlertService.processCovertAlert(covertAlert);

            // Should still send acknowledgment even if contacts fail to parse
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);
        }

        @Test
        @DisplayName("should handle WebSocket failure gracefully")
        void shouldHandleWebSocketFailure() {
            doThrow(new RuntimeException("Broker unavailable"))
                    .when(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);

            covertAlertService.processCovertAlert(covertAlert);

            // Should not propagate exception
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/covert-ack", covertAlert);
        }

        @Test
        @DisplayName("should calculate bounding box for responder search")
        void shouldCalculateBoundingBox() {
            when(userRepository.findVerifiedRespondersInArea(anyDouble(), anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());

            covertAlertService.processCovertAlert(covertAlert);

            double radiusKm = 50.0;
            double latDelta = radiusKm / 111.0;
            double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(6.5244)));

            verify(userRepository).findVerifiedRespondersInArea(
                    doubleThat(v -> Math.abs(v - (6.5244 - latDelta)) < 0.0001),
                    doubleThat(v -> Math.abs(v - (6.5244 + latDelta)) < 0.0001),
                    doubleThat(v -> Math.abs(v - (3.3792 - lonDelta)) < 0.0001),
                    doubleThat(v -> Math.abs(v - (3.3792 + lonDelta)) < 0.0001));
        }
    }
}
