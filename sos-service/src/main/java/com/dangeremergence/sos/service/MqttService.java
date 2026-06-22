package com.dangeremergence.sos.service;

import com.dangeremergence.sos.model.SOSAlert;
import com.google.gson.Gson;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.IMqttClient;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;

/**
 * MQTT service for the SOS microservice.
 * Publishes SOS alerts to the Mosquitto broker for IoT/mesh delivery.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class MqttService {

    private final IMqttClient mqttClient;
    private final Gson gson = new Gson();

    @Value("${mqtt.topic-prefix:danger/emergence/}")
    private String topicPrefix;

    /**
     * Publish an SOS alert to a specific MQTT topic.
     */
    public void publish(String topic, SOSAlert alert) {
        try {
            String fullTopic = topicPrefix + topic;
            String payload = gson.toJson(alert);
            MqttMessage message = new MqttMessage(payload.getBytes(StandardCharsets.UTF_8));
            message.setQos(2); // Exactly once delivery for SOS alerts
            message.setRetained(false);
            mqttClient.publish(fullTopic, message);
            log.debug("MQTT published to {}: alert {}", fullTopic, alert.getId());
        } catch (Exception e) {
            log.error("MQTT publish failed to topic {}: {}", topic, e.getMessage());
        }
    }

    /**
     * Publish an SOS alert to the general alert topic.
     */
    public void publishAlert(SOSAlert alert) {
        publish("alerts/new", alert);
    }
}
