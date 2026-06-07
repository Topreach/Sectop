package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
@Entity
@Table(name = "sos_alerts")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SOSAlert {

    @Id
    @Column(length = 36)
    private String id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "alert_type", nullable = false)
    private String alertType;

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

    @Column(nullable = false)
    private int priority;

    @Column(name = "is_silent")
    private boolean silent;

    @Column(nullable = false)
    @Enumerated(EnumType.STRING)
    private AlertStatus status;

    @Column(name = "mesh_relayed")
    private boolean meshRelayed;

    @Column(name = "acknowledged_by")
    private String acknowledgedBy;

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

    @Column(name = "resolved_at")
    private LocalDateTime resolvedAt;

    public enum AlertStatus {
        active, acknowledged, resolved, expired
    }
}
