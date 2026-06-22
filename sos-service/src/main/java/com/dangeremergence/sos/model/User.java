package com.dangeremergence.sos.model;

import jakarta.persistence.*;
import lombok.*;

/**
 * Minimal User entity for the SOS microservice.
 * <p>
 * Only fields needed for SOS alert processing are included.
 * Maps to the same `users` table in PostgreSQL.
 */
@Entity
@Table(name = "users")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class User {

    @Id
    @Column(length = 36)
    private String id;

    @Column(nullable = false, unique = true)
    private String phone;

    @Column(nullable = false)
    private String fullName;

    @Column(name = "fcm_token")
    private String fcmToken;

    @Column(name = "emergency_contacts", columnDefinition = "TEXT")
    private String emergencyContacts;

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    @Column(length = 20)
    @Enumerated(EnumType.STRING)
    private Role role;

    public enum Role {
        citizen, responder, guardian, coordinator, admin
    }
}
