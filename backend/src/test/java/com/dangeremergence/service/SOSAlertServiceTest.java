package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.SOSAlertRepository;
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
@DisplayName("SOSAlertService Unit Tests")
class SOSAlertServiceTest {

    @Mock
    private SOSAlertRepository alertRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private MqttService mqttService;

    @Mock
    private DroneService droneService;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private AlertPubSubService alertPubSubService;

    @Mock
    private FcmPushService fcmPushService;

    @Mock
    private SmsGatewayService smsGatewayService;

    @Mock
    private NigeriaLocationService nigeriaLocationService;

    @Mock
    private CovertAlertService covertAlertService;

    @InjectMocks
    private SOSAlertService sosAlertService;

    @Captor
    private ArgumentCaptor<SOSAlert> alertCaptor;

    private User testUser;
    private SOSAlert testAlert;
    private final String userId = "user-123";
    private final String alertId = "alert-456";
    private final String responderId = "responder-789";

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .id(userId)
                .name("Test User")
                .email("test@example.com")
                .phone("+2348012345678")
                .role(User.UserRole.citizen)
                .active(true)
                .build();

        testAlert = SOSAlert.builder()
                .id(alertId)
                .user(testUser)
                .alertType("fire")
                .description("Fire at market")
                .latitude(6.5244)
                .longitude(3.3792)
                .accuracy(50.0)
                .state("Lagos")
                .lga("Ikeja")
                .priority(8)
                .silent(false)
                .covert(false)
                .status(SOSAlert.AlertStatus.active)
                .meshRelayed(false)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
    }

    @Nested
    @DisplayName("createAlert()")
    class CreateAlert {

        @Test
        @DisplayName("should create alert with resolved geo info and trigger async processing")
        void shouldCreateAlertSuccessfully() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(nigeriaLocationService.resolve(6.5244, 3.3792)).thenReturn(new String[]{"Lagos", "Ikeja"});
            when(alertRepository.save(any(SOSAlert.class))).thenAnswer(invocation -> invocation.getArgument(0));

            SOSAlert result = sosAlertService.createAlert(
                    userId, "fire", "Fire at market",
                    6.5244, 3.3792, 50.0, 8, false, false);

            assertThat(result).isNotNull();
            assertThat(result.getAlertType()).isEqualTo("fire");
            assertThat(result.getState()).isEqualTo("Lagos");
            assertThat(result.getLga()).isEqualTo("Ikeja");
            assertThat(result.getStatus()).isEqualTo(SOSAlert.AlertStatus.active);
            assertThat(result.isCovert()).isFalse();
            assertThat(result.isMeshRelayed()).isFalse();
            verify(alertRepository).save(any(SOSAlert.class));
            verify(nigeriaLocationService).resolve(6.5244, 3.3792);
        }

        @Test
        @DisplayName("should throw when user not found")
        void shouldThrowWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> sosAlertService.createAlert(
                    "unknown", "fire", "desc", 6.5, 3.4, 50.0, 5, false, false))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("User not found");

            verify(alertRepository, never()).save(any());
        }

        @Test
        @DisplayName("should handle null lat/lng gracefully")
        void shouldHandleNullCoordinates() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(nigeriaLocationService.resolve(null, null)).thenReturn(new String[]{"Unknown", "Unknown"});
            when(alertRepository.save(any(SOSAlert.class))).thenAnswer(invocation -> invocation.getArgument(0));

            SOSAlert result = sosAlertService.createAlert(
                    userId, "fire", "desc", null, null, null, 5, false, false);

            assertThat(result.getState()).isEqualTo("Unknown");
            assertThat(result.getLga()).isEqualTo("Unknown");
        }
    }

    @Nested
    @DisplayName("processNewAlert() - covert mode")
    class ProcessNewAlertCovert {

        @Test
        @DisplayName("should route to CovertAlertService and skip public broadcasts when alert is covert")
        void shouldRouteToCovertService() {
            testAlert.setCovert(true);

            sosAlertService.processNewAlert(testAlert);

            verify(covertAlertService).processCovertAlert(testAlert);
            verify(mqttService, never()).publish(anyString(), any());
            verify(mqttService, never()).publishAlert(any());
            verify(droneService, never()).deployRelayIfNecessary(anyString(), anyString(), anyDouble(), anyDouble(), anyInt());
            verify(messagingTemplate, never()).convertAndSend(anyString(), any());
            verify(alertPubSubService, never()).publishAlert(any());
            verify(fcmPushService, never()).notifyAlertToNearbyUsers(any(), anyDouble());
            verify(smsGatewayService, never()).sendAlertSms(any(), anyString());
        }
    }

    @Nested
    @DisplayName("processNewAlert() - normal mode")
    class ProcessNewAlertNormal {

        @Test
        @DisplayName("should publish to MQTT, WebSocket, Redis, FCM, and SMS")
        void shouldPublishToAllChannels() {
            sosAlertService.processNewAlert(testAlert);

            // MQTT
            verify(mqttService).publish(eq("alerts/lagos/ikeja"), eq(testAlert));
            verify(mqttService).publish(eq("guardians/lagos/ikeja"), eq(testAlert));
            verify(mqttService).publishAlert(testAlert);

            // Drone
            verify(droneService).deployRelayIfNecessary("Ikeja", "Lagos", 6.5244, 3.3792, 8);

            // WebSocket
            verify(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);
            verify(messagingTemplate).convertAndSend(eq("/topic/alerts/lagos/ikeja"), eq(testAlert));
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/alerts", testAlert);

            // Redis Pub/Sub
            verify(alertPubSubService).publishAlert(testAlert);
            verify(alertPubSubService).publishGeoAlert(testAlert, "lagos", "ikeja");

            // FCM
            verify(fcmPushService).notifyAlertToNearbyUsers(testAlert, 10.0);

            // SMS
            verify(smsGatewayService).sendAlertSms(testAlert, "+2348012345678");
        }

        @Test
        @DisplayName("should skip SMS when user has no phone")
        void shouldSkipSmsWhenNoPhone() {
            testUser.setPhone(null);

            sosAlertService.processNewAlert(testAlert);

            verify(smsGatewayService, never()).sendAlertSms(any(), anyString());
        }

        @Test
        @DisplayName("should handle WebSocket failure gracefully")
        void shouldHandleWebSocketFailure() {
            doThrow(new RuntimeException("Connection refused"))
                    .when(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);

            sosAlertService.processNewAlert(testAlert);

            // Should not propagate exception — just log warning
            verify(mqttService).publishAlert(testAlert);
            verify(droneService).deployRelayIfNecessary(anyString(), anyString(), anyDouble(), anyDouble(), anyInt());
        }
    }

    @Nested
    @DisplayName("pushAlertToWebSocket()")
    class PushAlertToWebSocket {

        @Test
        @DisplayName("should push to global, geo, and user-specific topics")
        void shouldPushToAllTopics() {
            sosAlertService.pushAlertToWebSocket(testAlert);

            verify(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);
            verify(messagingTemplate).convertAndSend("/topic/alerts/lagos/ikeja", testAlert);
            verify(messagingTemplate).convertAndSendToUser(userId, "/queue/alerts", testAlert);
        }

        @Test
        @DisplayName("should handle null state/lga gracefully")
        void shouldHandleNullGeo() {
            testAlert.setState(null);
            testAlert.setLga(null);

            sosAlertService.pushAlertToWebSocket(testAlert);

            verify(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);
            verify(messagingTemplate).convertAndSend("/topic/alerts/unknown/unknown", testAlert);
        }

        @Test
        @DisplayName("should handle null user gracefully")
        void shouldHandleNullUser() {
            testAlert.setUser(null);

            sosAlertService.pushAlertToWebSocket(testAlert);

            verify(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);
            verify(messagingTemplate, never()).convertAndSendToUser(anyString(), anyString(), any());
        }

        @Test
        @DisplayName("should handle WebSocket failure gracefully")
        void shouldHandleFailure() {
            doThrow(new RuntimeException("Broker unavailable"))
                    .when(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);

            sosAlertService.pushAlertToWebSocket(testAlert);

            // Should not propagate exception
            verify(messagingTemplate).convertAndSend("/topic/alerts/new", testAlert);
        }
    }

    @Nested
    @DisplayName("acknowledgeAlert()")
    class AcknowledgeAlert {

        @Test
        @DisplayName("should set status to acknowledged and record responder")
        void shouldAcknowledgeAlert() {
            when(alertRepository.findById(alertId)).thenReturn(Optional.of(testAlert));
            when(alertRepository.save(any(SOSAlert.class))).thenAnswer(invocation -> invocation.getArgument(0));

            SOSAlert result = sosAlertService.acknowledgeAlert(alertId, responderId);

            assertThat(result.getStatus()).isEqualTo(SOSAlert.AlertStatus.acknowledged);
            assertThat(result.getAcknowledgedBy()).isEqualTo(responderId);
            assertThat(result.getUpdatedAt()).isNotNull();
        }

        @Test
        @DisplayName("should throw when alert not found")
        void shouldThrowWhenNotFound() {
            when(alertRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> sosAlertService.acknowledgeAlert("unknown", responderId))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Alert not found");
        }
    }

    @Nested
    @DisplayName("resolveAlert()")
    class ResolveAlert {

        @Test
        @DisplayName("should set status to resolved and record resolvedAt")
        void shouldResolveAlert() {
            when(alertRepository.findById(alertId)).thenReturn(Optional.of(testAlert));
            when(alertRepository.save(any(SOSAlert.class))).thenAnswer(invocation -> invocation.getArgument(0));

            SOSAlert result = sosAlertService.resolveAlert(alertId);

            assertThat(result.getStatus()).isEqualTo(SOSAlert.AlertStatus.resolved);
            assertThat(result.getResolvedAt()).isNotNull();
            assertThat(result.getUpdatedAt()).isNotNull();
        }

        @Test
        @DisplayName("should throw when alert not found")
        void shouldThrowWhenNotFound() {
            when(alertRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> sosAlertService.resolveAlert("unknown"))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Alert not found");
        }
    }

    @Nested
    @DisplayName("getActiveAlerts()")
    class GetActiveAlerts {

        @Test
        @DisplayName("should return active alerts ordered by priority")
        void shouldReturnActiveAlerts() {
            when(alertRepository.findByStatusOrderByPriorityDescCreatedAtDesc(SOSAlert.AlertStatus.active))
                    .thenReturn(List.of(testAlert));

            List<SOSAlert> result = sosAlertService.getActiveAlerts();

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getId()).isEqualTo(alertId);
        }

        @Test
        @DisplayName("should return empty list when no active alerts")
        void shouldReturnEmptyWhenNone() {
            when(alertRepository.findByStatusOrderByPriorityDescCreatedAtDesc(SOSAlert.AlertStatus.active))
                    .thenReturn(List.of());

            List<SOSAlert> result = sosAlertService.getActiveAlerts();

            assertThat(result).isEmpty();
        }
    }

    @Nested
    @DisplayName("getAlertsForUser()")
    class GetAlertsForUser {

        @Test
        @DisplayName("should return alerts for given user")
        void shouldReturnUserAlerts() {
            when(alertRepository.findByUserIdOrderByCreatedAtDesc(userId))
                    .thenReturn(List.of(testAlert));

            List<SOSAlert> result = sosAlertService.getAlertsForUser(userId);

            assertThat(result).hasSize(1);
        }
    }

    @Nested
    @DisplayName("getAlertsInArea()")
    class GetAlertsInArea {

        @Test
        @DisplayName("should calculate bounding box and query repository")
        void shouldCalculateBoundingBox() {
            double lat = 6.5244;
            double lng = 3.3792;
            double radiusKm = 10.0;
            double latDelta = radiusKm / 111.0;
            double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(lat)));

            when(alertRepository.findAlertsInArea(
                    lat - latDelta, lat + latDelta,
                    lng - lonDelta, lng + lonDelta,
                    SOSAlert.AlertStatus.active))
                    .thenReturn(List.of(testAlert));

            List<SOSAlert> result = sosAlertService.getAlertsInArea(lat, lng, radiusKm);

            assertThat(result).hasSize(1);
            verify(alertRepository).findAlertsInArea(
                    doubleThat(v -> Math.abs(v - (lat - latDelta)) < 0.0001),
                    doubleThat(v -> Math.abs(v - (lat + latDelta)) < 0.0001),
                    doubleThat(v -> Math.abs(v - (lng - lonDelta)) < 0.0001),
                    doubleThat(v -> Math.abs(v - (lng + lonDelta)) < 0.0001),
                    eq(SOSAlert.AlertStatus.active));
        }
    }

    @Nested
    @DisplayName("getAlertsSince()")
    class GetAlertsSince {

        @Test
        @DisplayName("should return alerts since given time")
        void shouldReturnAlertsSince() {
            LocalDateTime since = LocalDateTime.now().minusHours(1);
            when(alertRepository.findActiveAlertsSince(SOSAlert.AlertStatus.active, since))
                    .thenReturn(List.of(testAlert));

            List<SOSAlert> result = sosAlertService.getAlertsSince(since);

            assertThat(result).hasSize(1);
        }
    }

    @Nested
    @DisplayName("cleanupExpiredAlerts()")
    class CleanupExpiredAlerts {

        @Test
        @DisplayName("should mark alerts older than 24h as expired")
        void shouldExpireOldAlerts() {
            SOSAlert oldAlert = SOSAlert.builder()
                    .id("old-alert")
                    .user(testUser)
                    .status(SOSAlert.AlertStatus.active)
                    .build();

            when(alertRepository.findExpiredAlerts(eq(SOSAlert.AlertStatus.active), any(LocalDateTime.class)))
                    .thenReturn(List.of(oldAlert));

            sosAlertService.cleanupExpiredAlerts();

            verify(alertRepository).saveAll(alertCaptor.capture());
            List<SOSAlert> saved = (List<SOSAlert>) alertCaptor.getValue();
            assertThat(saved).hasSize(1);
            assertThat(saved.get(0).getStatus()).isEqualTo(SOSAlert.AlertStatus.expired);
            assertThat(saved.get(0).getUpdatedAt()).isNotNull();
        }

        @Test
        @DisplayName("should do nothing when no expired alerts")
        void shouldDoNothingWhenNoneExpired() {
            when(alertRepository.findExpiredAlerts(eq(SOSAlert.AlertStatus.active), any(LocalDateTime.class)))
                    .thenReturn(List.of());

            sosAlertService.cleanupExpiredAlerts();

            verify(alertRepository, never()).saveAll(any());
        }
    }

    @Nested
    @DisplayName("getActiveAlertCount()")
    class GetActiveAlertCount {

        @Test
        @DisplayName("should return count of active alerts")
        void shouldReturnCount() {
            when(alertRepository.countByStatus(SOSAlert.AlertStatus.active)).thenReturn(5L);

            long count = sosAlertService.getActiveAlertCount();

            assertThat(count).isEqualTo(5L);
        }
    }
}
