package com.dangeremergence.model;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "emergency_bypass_audit")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EmergencyBypassAudit {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String sessionId;
    private String phone;
    private String clientIp;
    private String method; // key | rate_limit
    private boolean success;
    private boolean tokenIssued;

    @CreationTimestamp
    private LocalDateTime createdAt;
}
