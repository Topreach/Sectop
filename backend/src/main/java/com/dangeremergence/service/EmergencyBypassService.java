package com.dangeremergence.service;

import com.dangeremergence.model.EmergencyBypassAudit;
import com.dangeremergence.repository.EmergencyBypassAuditRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class EmergencyBypassService {

    private final EmergencyBypassAuditRepository repo;

    public EmergencyBypassService(EmergencyBypassAuditRepository repo) {
        this.repo = repo;
    }

    public EmergencyBypassAudit record(String sessionId, String phone, String clientIp, String method, boolean success, boolean tokenIssued) {
        EmergencyBypassAudit a = EmergencyBypassAudit.builder()
                .sessionId(sessionId)
                .phone(phone)
                .clientIp(clientIp)
                .method(method)
                .success(success)
                .tokenIssued(tokenIssued)
                .build();
        return repo.save(a);
    }
}
