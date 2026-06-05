package com.dangeremergence.service;

import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.ZoneRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Service
@Transactional
public class ZoneService {

    private final ZoneRepository zoneRepository;

    @Autowired
    public ZoneService(ZoneRepository zoneRepository) {
        this.zoneRepository = zoneRepository;
    }

    public Zone createZone(Zone zone) {
        zone.setCreatedAt(LocalDateTime.now());
        zone.setUpdatedAt(LocalDateTime.now());
        return zoneRepository.save(zone);
    }

    public Optional<Zone> getZoneById(Long id) {
        return zoneRepository.findById(id);
    }

    public List<Zone> getActiveZones() {
        return zoneRepository.findByTypeAndStatus(
            Zone.ZoneType.safety, Zone.ZoneStatus.active);
    }

    public List<Zone> getZonesByTypeAndStatus(Zone.ZoneType type, Zone.ZoneStatus status) {
        return zoneRepository.findByTypeAndStatus(type, status);
    }

    public List<Zone> getZonesInArea(double north, double south, double east, double west) {
        return zoneRepository.findZonesInArea(north, south, east, west);
    }

    public List<Zone> getZonesSince(LocalDateTime since) {
        return zoneRepository.findZonesSince(since);
    }

    public Zone updateZone(Zone zone) {
        zone.setUpdatedAt(LocalDateTime.now());
        return zoneRepository.save(zone);
    }

    public void deactivateZone(Long zoneId) {
        zoneRepository.findById(zoneId).ifPresent(zone -> {
            zone.setStatus(Zone.ZoneStatus.inactive);
            zone.setUpdatedAt(LocalDateTime.now());
            zoneRepository.save(zone);
        });
    }

    public void activateZone(Long zoneId) {
        zoneRepository.findById(zoneId).ifPresent(zone -> {
            zone.setStatus(Zone.ZoneStatus.active);
            zone.setUpdatedAt(LocalDateTime.now());
            zoneRepository.save(zone);
        });
    }

    public void expireZone(Long zoneId) {
        zoneRepository.findById(zoneId).ifPresent(zone -> {
            zone.setStatus(Zone.ZoneStatus.expired);
            zone.setUpdatedAt(LocalDateTime.now());
            zoneRepository.save(zone);
        });
    }

    public int cleanupExpiredZones() {
        List<Zone> expiredZones = zoneRepository.findExpiredZones(LocalDateTime.now());
        zoneRepository.deleteAll(expiredZones);
        return expiredZones.size();
    }

    public List<Zone> getDangerZones() {
        return zoneRepository.findByTypeAndStatus(
            Zone.ZoneType.danger, Zone.ZoneStatus.active);
    }

    public List<Zone> getRestrictedZones() {
        return zoneRepository.findByTypeAndStatus(
            Zone.ZoneType.restricted, Zone.ZoneStatus.active);
    }

    public long getActiveZoneCount() {
        return zoneRepository.count();
    }
}
