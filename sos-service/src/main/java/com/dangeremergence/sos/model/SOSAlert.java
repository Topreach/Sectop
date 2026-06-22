package com.dangeremergence.sos.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * SOS Alert entity — shared with the main backend database.
 * <p>
 * This model maps to the same `sos_alerts` table in PostgreSQL.
 * The SOS microservice (port 8081) and the main backend (port 8080)
 * both read/write to the same table.
 */
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

    @Column(name = "user_id", nullable = false, length = 36)
    private String userId;

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

    @Column(name = "is_covert")
    private boolean covert;

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

    @Column(name = "resolved_at")
    private LocalDateTime resolvedAt;

    @PrePersist
    public void ensureId() {
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
    }

    public enum AlertStatus {
        active, acknowledged, resolved, expired
    }
}
