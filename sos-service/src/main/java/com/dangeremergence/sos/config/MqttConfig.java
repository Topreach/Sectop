package com.dangeremergence.sos.config;

import org.eclipse.paho.client.mqttv3.IMqttClient;
import org.eclipse.paho.client.mqttv3.MqttClient;
import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.eclipse.paho.client.mqttv3.MqttException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.UUID;

/**
 * MQTT configuration for the SOS microservice.
 * Connects to the same Mosquitto broker as the main app.
 */
@Configuration
public class MqttConfig {

    @Value("${mqtt.broker:tcp://localhost:1883}")
    private String brokerUrl;

    @Value("${mqtt.client-id:sos-service}")
    private String clientId;

    @Bean
    public IMqttClient mqttClient() throws MqttException {
        String uniqueClientId = clientId + "-" + UUID.randomUUID().toString().substring(0, 8);
        IMqttClient client = new MqttClient(brokerUrl, uniqueClientId);

        MqttConnectOptions options = new MqttConnectOptions();
        options.setAutomaticReconnect(true);
        options.setCleanSession(true);
        options.setConnectionTimeout(10);

        client.connect(options);
        return client;
    }
}
