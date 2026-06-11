package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Represents a crowdsourced incident report (kidnapping, terrorism, banditry,
 * suspicious activity) with GPS coordinates for heatmap visualization
 * and pattern analysis.
 */
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
@Entity
@Table(name = "incidents")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Incident {

    @Id
    @Column(length = 36)
    private String id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "reporter_id")
    private User reporter;

    @Column(name = "incident_type", nullable = false, length = 100)
    private String incidentType;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    private Double accuracy;

    @Column(length = 50)
    private String state;

    @Column(length = 50)
    private String lga;

    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private IncidentSeverity severity;

    @Column(name = "is_anonymous")
    private boolean anonymous;

    @Column(name = "is_verified")
    private boolean verified;

    @Column(name = "verified_by", length = 36)
    private String verifiedBy;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private IncidentStatus status;

    @Column(name = "upvote_count")
    private int upvoteCount;

    @Column(name = "witness_count")
    private int witnessCount;

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

    public enum IncidentType {
        kidnapping, terrorism, banditry, armed_robbery, suspicious_activity,
        herdsmen_attack, cult_violence, ritual_killings, political_violence,
        communal_clash, other
    }

    public enum IncidentSeverity {
        low, medium, high, critical
    }

    public enum IncidentStatus {
        reported, under_review, verified, resolved, dismissed
    }
}
