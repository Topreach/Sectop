package com.dangeremergence.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Logs each ad watch for audit and daily limit enforcement.
 * Maps to the {@code ad_watch_logs} table.
 */
@Entity
@Table(name = "ad_watch_logs")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AdWatchLog {

    @Id
    @Column(length = 36)
    private String id;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "points_earned", nullable = false)
    @Builder.Default
    private Integer pointsEarned = 10;

    @Column(name = "ad_provider", length = 50, nullable = false)
    @Builder.Default
    private String adProvider = "unknown";

    @Column(name = "watched_at", nullable = false, updatable = false)
    private LocalDateTime watchedAt;

    @PrePersist
    protected void onCreate() {
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
        if (watchedAt == null) {
            watchedAt = LocalDateTime.now();
        }
    }
}
