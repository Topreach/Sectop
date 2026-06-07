package com.dangeremergence.repository;

import com.dangeremergence.model.EmergencyBypassAudit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface EmergencyBypassAuditRepository extends JpaRepository<EmergencyBypassAudit, Long> {
}
