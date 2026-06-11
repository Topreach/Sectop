package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Represents an anonymous tip-off / intelligence report from a citizen.
 * Used for reporting planned attacks, suspicious activity, etc.
 */
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
@Entity
@Table(name = "tip_offs")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TipOff {

    @Id
    @Column(length = 36)
    private String id;

    @Column(name = "tip_type", nullable = false, length = 50)
    @Enumerated(EnumType.STRING)
    private TipType tipType;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String description;

    private Double latitude;
    private Double longitude;
    private Double accuracy;

    @Column(length = 50)
    private String state;

    @Column(length = 50)
    private String lga;

    @Column(name = "occurred_at")
    private LocalDateTime occurredAt;

    @Column(name = "target_description", columnDefinition = "TEXT")
    private String targetDescription;

    @Column(name = "suspect_description", columnDefinition = "TEXT")
    private String suspectDescription;

    @Column(name = "threat_score")
    private int threatScore;

    @Column(name = "is_anonymous")
    private boolean anonymous;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "reporter_id")
    private User reporter;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private TipStatus status;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "reviewed_by")
    private User reviewedBy;

    @Column(name = "review_notes", columnDefinition = "TEXT")
    private String reviewNotes;

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

    public enum TipType {
        planned_attack, suspicious_person, suspicious_vehicle,
        hidden_weapons, kidnapping_plot, bombing_plot, other
    }

    public enum TipStatus {
        pending, under_review, actionable, dismissed, forwarded
    }
}
