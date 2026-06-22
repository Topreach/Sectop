package com.dangeremergence.sos.service;

import com.dangeremergence.sos.model.SOSAlert;
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
 * Redis Pub/Sub service for cross-server alert broadcast.
 * Ensures alerts published on one server instance are delivered to all instances.
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

    public void publishAlert(SOSAlert alert) {
        try {
            redisTemplate.convertAndSend(ALERT_CHANNEL, alert);
            log.debug("Alert published to Redis channel: {}", alert.getId());
        } catch (Exception e) {
            log.error("Failed to publish alert to Redis: {}", e.getMessage());
        }
    }

    public void publishGeoAlert(SOSAlert alert, String stateSlug, String lgaSlug) {
        try {
            String geoChannel = GEO_ALERT_PREFIX + stateSlug + "/" + lgaSlug;
            redisTemplate.convertAndSend(geoChannel, alert);
        } catch (Exception e) {
            log.error("Failed to publish geo alert to Redis: {}", e.getMessage());
        }
    }

    @SuppressWarnings("unused")
    public void onAlertReceived(SOSAlert alert) {
        log.info("Alert received via Redis pub/sub: {} (type={})", alert.getId(), alert.getAlertType());
        try {
            String stateSlug = alert.getState() != null
                    ? alert.getState().toLowerCase().replace(" ", "_") : "unknown";
            String lgaSlug = alert.getLga() != null
                    ? alert.getLga().toLowerCase().replace(" ", "_") : "unknown";

            messagingTemplate.convertAndSend("/topic/alerts/new", alert);

            String geoDest = String.format("/topic/alerts/%s/%s", stateSlug, lgaSlug);
            messagingTemplate.convertAndSend(geoDest, alert);

            log.debug("Cross-server WebSocket push for alert: {}", alert.getId());
        } catch (Exception e) {
            log.warn("Cross-server WebSocket push failed for alert {}: {}", alert.getId(), e.getMessage());
        }
    }
}
