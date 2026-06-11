package com.dangeremergence.service;

import com.dangeremergence.model.RadioBroadcast;
import com.dangeremergence.model.RadioBroadcast.BroadcastSeverity;
import com.dangeremergence.model.RadioBroadcast.BroadcastStatus;
import com.dangeremergence.model.RadioBroadcast.BroadcastType;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.RadioBroadcastRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;

/**
 * Service for managing emergency radio broadcasts.
 * When internet is cut, radio is the only way to reach rural communities.
 * All heavy logic (TTS generation, audio encoding) runs on the backend.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class RadioBroadcastService {

    private final RadioBroadcastRepository radioBroadcastRepository;
    private final UserRepository userRepository;
    private final MqttService mqttService;

    /**
     * Create a new radio broadcast and publish via MQTT to radio gateway.
     */
    @Transactional
    public RadioBroadcast createRadioBroadcast(String title, String message,
                                                String language, String severity,
                                                String broadcastType, Double targetFrequency,
                                                String targetState, String targetLga,
                                                String ttsVoice, boolean isAnonymous,
                                                String createdById) {
        User creator = createdById != null ?
                userRepository.findById(createdById).orElse(null) : null;

        BroadcastSeverity sev;
        try {
            sev = BroadcastSeverity.valueOf(severity != null ? severity.toLowerCase() : "urgent");
        } catch (IllegalArgumentException e) {
            sev = BroadcastSeverity.urgent;
        }

        BroadcastType type;
        try {
            type = BroadcastType.valueOf(broadcastType != null ? broadcastType.toLowerCase() : "emergency");
        } catch (IllegalArgumentException e) {
            type = BroadcastType.emergency;
        }

        // Generate TTS audio (simulated - in production would call Google TTS / eSpeak)
        String audioFileUrl = generateAudio(message, language);

        RadioBroadcast broadcast = RadioBroadcast.builder()
                .id(UUID.randomUUID().toString())
                .title(title)
                .message(message)
                .language(language != null ? language : "en")
                .severity(sev)
                .broadcastType(type)
                .targetFrequency(targetFrequency)
                .targetState(targetState)
                .targetLga(targetLga)
                .audioDurationSeconds(estimateAudioDuration(message))
                .audioFileUrl(audioFileUrl)
                .ttsVoice(ttsVoice != null ? ttsVoice : "default")
                .anonymous(isAnonymous)
                .createdBy(creator)
                .status(BroadcastStatus.pending)
                .broadcastCount(0)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        RadioBroadcast saved = radioBroadcastRepository.save(broadcast);
        log.info("Radio broadcast created: {} language={} target={}/{}",
                saved.getId(), language, targetState, targetLga);

        // Publish to MQTT for radio gateway device
        publishToMqtt(saved);

        // Mark as broadcasting
        saved.setStatus(BroadcastStatus.broadcasting);
        saved.setLastBroadcastAt(LocalDateTime.now());
        radioBroadcastRepository.save(saved);

        return saved;
    }

    /**
     * Get broadcast history.
     */
    @Transactional(readOnly = true)
    public List<RadioBroadcast> getBroadcastHistory() {
        return radioBroadcastRepository.findAllByOrderByCreatedAtDesc();
    }

    /**
     * Get broadcast by ID.
     */
    @Transactional(readOnly = true)
    public Optional<RadioBroadcast> getBroadcastById(String id) {
        return radioBroadcastRepository.findById(id);
    }

    /**
     * Retry a failed broadcast.
     */
    @Transactional
    public RadioBroadcast retryBroadcast(String id) {
        RadioBroadcast broadcast = radioBroadcastRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Radio broadcast not found: " + id));

        broadcast.setStatus(BroadcastStatus.broadcasting);
        broadcast.setBroadcastCount(broadcast.getBroadcastCount() + 1);
        broadcast.setLastBroadcastAt(LocalDateTime.now());
        broadcast.setUpdatedAt(LocalDateTime.now());

        // Re-publish to MQTT
        publishToMqtt(broadcast);

        RadioBroadcast saved = radioBroadcastRepository.save(broadcast);
        log.info("Radio broadcast retried: {} count={}", saved.getId(), saved.getBroadcastCount());
        return saved;
    }

    /**
     * Generate TTS audio URL for the given message and language.
     * In production, this would call Google Cloud TTS, Amazon Polly, or eSpeak.
     */
    private String generateAudio(String message, String language) {
        // Simulated: generate a deterministic URL based on message hash
        int messageHash = Math.abs(message.hashCode());
        String lang = language != null ? language : "en";
        return String.format("/audio/broadcasts/%s/%d.mp3", lang, messageHash);
    }

    /**
     * Estimate audio duration based on word count.
     * Average speaking rate: ~150 words per minute.
     */
    private int estimateAudioDuration(String message) {
        if (message == null || message.isEmpty()) return 0;
        int wordCount = message.split("\\s+").length;
        return Math.max(5, (int) Math.ceil((double) wordCount / 150.0 * 60.0));
    }

    /**
     * Publish broadcast to MQTT for the radio gateway device.
     * The radio gateway (ESP32/SDR) subscribes to these topics and transmits over FM.
     */
    private void publishToMqtt(RadioBroadcast broadcast) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", broadcast.getId());
        payload.put("title", broadcast.getTitle());
        payload.put("message", broadcast.getMessage());
        payload.put("language", broadcast.getLanguage());
        payload.put("severity", broadcast.getSeverity().name());
        payload.put("broadcastType", broadcast.getBroadcastType().name());
        payload.put("targetFrequency", broadcast.getTargetFrequency());
        payload.put("targetState", broadcast.getTargetState());
        payload.put("targetLga", broadcast.getTargetLga());
        payload.put("audioDurationSeconds", broadcast.getAudioDurationSeconds());
        payload.put("audioFileUrl", broadcast.getAudioFileUrl());
        payload.put("ttsVoice", broadcast.getTtsVoice());
        payload.put("status", broadcast.getStatus().name());
        payload.put("broadcastCount", broadcast.getBroadcastCount());
        payload.put("createdAt", broadcast.getCreatedAt() != null ?
                broadcast.getCreatedAt().toString() : null);

        // Publish to radio-specific topic
        mqttService.publish("radio/broadcasts/new", payload);

        // Also publish to state-specific radio topic if targeted
        if (broadcast.getTargetState() != null) {
            mqttService.publish("radio/broadcasts/state/" + broadcast.getTargetState(), payload);
        }

        log.info("Published radio broadcast {} to MQTT", broadcast.getId());
    }
}
