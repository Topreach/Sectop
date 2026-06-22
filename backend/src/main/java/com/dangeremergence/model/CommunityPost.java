package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Represents a community post with photo/video media.
 * Users can post incident media from their environment for
 * crowdsourced situational awareness.
 */
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
@Entity
@Table(name = "community_posts")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CommunityPost {

    public enum MediaType {
        image, video
    }

    public enum PostStatus {
        active, flagged, removed
    }

    @Id
    @Column(length = 36)
    private String id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(columnDefinition = "TEXT")
    private String caption;

    @Column(name = "media_url", nullable = false, length = 512)
    private String mediaUrl;

    @Column(name = "media_type", nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private MediaType mediaType;

    private Double latitude;

    private Double longitude;

    @Column(name = "location_name", length = 255)
    private String locationName;

    @Column(name = "is_anonymous")
    private boolean isAnonymous;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private PostStatus status;

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
        if (status == null) {
            status = PostStatus.active;
        }
        if (mediaType == null) {
            mediaType = MediaType.image;
        }
    }
}
