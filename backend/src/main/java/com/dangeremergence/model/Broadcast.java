package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Represents a mass alert/broadcast sent to users in a geographic area.
 * Used for emergency warnings about kidnappings, terrorist attacks, etc.
 */
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
@Entity
@Table(name = "broadcasts")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Broadcast {

    @Id
    @Column(length = 36)
    private String id;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String message;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private BroadcastSeverity severity;

    @Column(name = "broadcast_type", nullable = false, length = 50)
    @Enumerated(EnumType.STRING)
    private BroadcastType broadcastType;

    @Column(name = "target_state", length = 50)
    private String targetState;

    @Column(name = "target_lga", length = 50)
    private String targetLga;

    @Column(name = "target_roles", length = 255)
    private String targetRoles;

    private Double latitude;
    private Double longitude;

    @Column(name = "radius_km")
    private Double radiusKm;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "created_by")
    private User createdBy;

    @Column(name = "is_active")
    private boolean active;

    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

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
        general, evacuation, curfew, manhunt, school_closure, weather, security
    }
}
