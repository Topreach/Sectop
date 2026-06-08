package com.dangeremergence.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.IMqttClient;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;

@Service
@RequiredArgsConstructor
@Slf4j
public class MqttService {

    private final IMqttClient mqttClient;
    private final ObjectMapper objectMapper;

    @Value("${mqtt.topic-prefix:danger/emergence/}")
    private String topicPrefix;

    @PostConstruct
    public void init() {
        try {
            if (!mqttClient.isConnected()) {
                mqttClient.connect();
                log.info("Connected to MQTT broker");
            }
        } catch (Exception e) {
            log.error("Failed to connect to MQTT broker", e);
        }
    }

    public void publish(String topic, Object payload) {
        try {
            String fullTopic = topicPrefix + topic;
            String jsonPayload = objectMapper.writeValueAsString(payload);
            MqttMessage message = new MqttMessage(jsonPayload.getBytes());
            message.setQos(1); // At least once delivery
            mqttClient.publish(fullTopic, message);
            log.debug("Published MQTT message to topic: {}", fullTopic);
        } catch (Exception e) {
            log.error("Failed to publish MQTT message", e);
        }
    }

    public void publishAlert(Object alert) {
        publish("alerts/new", alert);
    }

    public void publishZoneUpdate(Object zone) {
        publish("zones/update", zone);
    }
}
