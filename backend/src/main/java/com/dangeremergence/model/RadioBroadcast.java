package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Represents an emergency radio broadcast for FM transmission.
 * Used when internet is cut — radio is the only way to reach rural communities.
 */
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
@Entity
@Table(name = "radio_broadcasts")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RadioBroadcast {

    @Id
    @Column(length = 36)
    private String id;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String message;

    @Column(length = 20)
    private String language;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private BroadcastSeverity severity;

    @Column(name = "broadcast_type", nullable = false, length = 50)
    @Enumerated(EnumType.STRING)
    private BroadcastType broadcastType;

    @Column(name = "target_frequency")
    private Double targetFrequency;

    @Column(name = "target_state", length = 50)
    private String targetState;

    @Column(name = "target_lga", length = 50)
    private String targetLga;

    @Column(name = "audio_duration_seconds")
    private Integer audioDurationSeconds;

    @Column(name = "audio_file_url", columnDefinition = "TEXT")
    private String audioFileUrl;

    @Column(name = "tts_voice", length = 50)
    private String ttsVoice;

    @Column(name = "is_anonymous")
    private boolean anonymous;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "created_by")
    private User createdBy;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private BroadcastStatus status;

    @Column(name = "broadcast_count")
    private int broadcastCount;

    @Column(name = "last_broadcast_at")
    private LocalDateTime lastBroadcastAt;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    public void ensureId() {
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
    }

    public enum BroadcastSeverity {
        info, warning, urgent, critical
    }

    public enum BroadcastType {
        emergency, public_safety, evacuation, curfew, manhunt, school_closure, weather
    }

    public enum BroadcastStatus {
        pending, broadcasting, completed, failed
    }
}
