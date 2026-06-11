package com.dangeremergence.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * Evidence entity - stores metadata for photo/video/audio evidence
 * captured during SOS alerts, incident reports, or tip-offs.
 *
 * Files are stored as base64 in the database for offline-first sync.
 * In production, large files should use S3/MinIO with URL references.
 */
@Entity
@Table(name = "evidence")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
public class Evidence {

    @Id
    @Column(length = 64)
    private String id;

    /** ID of the parent entity (SOS alert, incident, or tip-off). */
    @Column(name = "parent_id", nullable = false, length = 64)
    private String parentId;

    /** Type of parent: "alert", "incident", or "tip". */
    @Column(name = "parent_type", nullable = false, length = 16)
    private String parentType;

    /** Evidence type: "photo", "video", or "audio". */
    @Column(name = "evidence_type", nullable = false, length = 16)
    private String evidenceType;

    /** Original file name. */
    @Column(name = "file_name", length = 255)
    private String fileName;

    /** MIME type (e.g., image/jpeg, video/mp4, audio/mp4). */
    @Column(name = "mime_type", length = 64)
    private String mimeType;

    /** File size in bytes. */
    @Column(name = "size_bytes")
    private Long sizeBytes;

    /** Base64-encoded file content for offline-first sync. */
    @Lob
    @Column(name = "file_content", columnDefinition = "MEDIUMTEXT")
    private String fileContent;

    /** URL to the file if stored externally (S3/MinIO). */
    @Column(name = "file_url", length = 1024)
    private String fileUrl;

    /** Latitude where evidence was captured. */
    @Column(name = "latitude")
    private Double latitude;

    /** Longitude where evidence was captured. */
    @Column(name = "longitude")
    private Double longitude;

    /** When the evidence was captured. */
    @Column(name = "captured_at", nullable = false)
    private LocalDateTime capturedAt;

    /** When the evidence record was created. */
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
