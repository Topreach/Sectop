package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.listener.ChannelTopic;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;
import org.springframework.data.redis.listener.adapter.MessageListenerAdapter;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;

/**
 * Redis Pub/Sub service for instant cross-server alert broadcast.
 *
 * When multiple backend instances are running (horizontal scaling),
 * this service ensures an alert published on one server is instantly
 * delivered to all other servers via Redis pub/sub channels.
 *
 * Delivery chain:
 *   SOSAlertService -> AlertPubSubService.publish()
 *   -> Redis Channel -> All subscribers (all server instances)
 *   -> WebSocket/STOMP push to connected clients on each server
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class AlertPubSubService {

    private static final String ALERT_CHANNEL = "alerts:new";
    private static final String GEO_ALERT_PREFIX = "alerts:geo:";

    private final RedisTemplate<String, Object> redisTemplate;
    private final RedisMessageListenerContainer redisListenerContainer;
    private final SimpMessagingTemplate messagingTemplate;

    private MessageListenerAdapter listenerAdapter;

    @PostConstruct
    public void init() {
        // Subscribe to the global alert channel
        listenerAdapter = new MessageListenerAdapter(this, "onAlertReceived");
        listenerAdapter.setSerializer(redisTemplate.getValueSerializer());
        redisListenerContainer.addMessageListener(listenerAdapter, new ChannelTopic(ALERT_CHANNEL));
        log.info("AlertPubSubService: Subscribed to Redis channel '{}'", ALERT_CHANNEL);
    }

    @PreDestroy
    public void destroy() {
        if (listenerAdapter != null) {
            redisListenerContainer.removeMessageListener(listenerAdapter);
        }
    }

    /**
     * Publish an alert to all backend instances via Redis pub/sub.
     * Called by SOSAlertService after creating an alert.
     */
    public void publishAlert(SOSAlert alert) {
        try {
            redisTemplate.convertAndSend(ALERT_CHANNEL, alert);
            log.debug("Alert published to Redis channel: {}", alert.getId());
        } catch (Exception e) {
            log.error("Failed to publish alert to Redis: {}", e.getMessage());
        }
    }

    /**
     * Publish alert to a geo-specific channel (state/LGA).
     */
    public void publishGeoAlert(SOSAlert alert, String stateSlug, String lgaSlug) {
        try {
            String geoChannel = GEO_ALERT_PREFIX + stateSlug + "/" + lgaSlug;
            redisTemplate.convertAndSend(geoChannel, alert);
        } catch (Exception e) {
            log.error("Failed to publish geo alert to Redis: {}", e.getMessage());
        }
    }

    /**
     * Callback when an alert is received from Redis pub/sub.
     * This is invoked on ALL server instances, so each instance
     * can push to its own connected WebSocket clients.
     */
    @SuppressWarnings("unused")
    public void onAlertReceived(SOSAlert alert) {
        log.info("Alert received via Redis pub/sub: {} (type={})", alert.getId(), alert.getAlertType());
        // Forward to WebSocket/STOMP on THIS server instance
        try {
            String stateSlug = alert.getState() != null
                    ? alert.getState().toLowerCase().replace(" ", "_") : "unknown";
            String lgaSlug = alert.getLga() != null
                    ? alert.getLga().toLowerCase().replace(" ", "_") : "unknown";

            // Push to global alert topic
            messagingTemplate.convertAndSend("/topic/alerts/new", alert);

            // Push to geo-specific topic
            String geoDest = String.format("/topic/alerts/%s/%s", stateSlug, lgaSlug);
            messagingTemplate.convertAndSend(geoDest, alert);

            // Push to user-specific queue if user is available
            if (alert.getUser() != null && alert.getUser().getId() != null) {
                messagingTemplate.convertAndSendToUser(alert.getUser().getId(), "/queue/alerts", alert);
            }

            log.debug("Cross-server WebSocket push for alert: {}", alert.getId());
        } catch (Exception e) {
            log.warn("Cross-server WebSocket push failed for alert {}: {}", alert.getId(), e.getMessage());
        }
    }
}
