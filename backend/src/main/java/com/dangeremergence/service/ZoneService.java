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

    public Optional<Zone> getZoneById(String id) {
        return zoneRepository.findById(id);
    }

    public List<Zone> getActiveZones() {
        return zoneRepository.findByStatus(Zone.ZoneStatus.active);
    }

    public List<Zone> getZonesByTypeAndStatus(Zone.ZoneType type, Zone.ZoneStatus status) {
        return zoneRepository.findByTypeAndStatus(type.name(), status);
    }

    public List<Zone> getZonesInArea(double north, double south, double east, double west) {
        return zoneRepository.findZonesInArea(south, north, west, east, Zone.ZoneStatus.active);
    }

    public List<Zone> getZonesSince(LocalDateTime since) {
        return zoneRepository.findZonesSince(since, Zone.ZoneStatus.active);
    }

    public Zone updateZone(Zone zone) {
        zone.setUpdatedAt(LocalDateTime.now());
        return zoneRepository.save(zone);
    }

    public void deactivateZone(String zoneId) {
        zoneRepository.findById(zoneId).ifPresent(zone -> {
            zone.setStatus(Zone.ZoneStatus.inactive);
            zone.setUpdatedAt(LocalDateTime.now());
            zoneRepository.save(zone);
        });
    }

    public void activateZone(String zoneId) {
        zoneRepository.findById(zoneId).ifPresent(zone -> {
            zone.setStatus(Zone.ZoneStatus.active);
            zone.setUpdatedAt(LocalDateTime.now());
            zoneRepository.save(zone);
        });
    }

    public void expireZone(String zoneId) {
        zoneRepository.findById(zoneId).ifPresent(zone -> {
            zone.setStatus(Zone.ZoneStatus.expired);
            zone.setUpdatedAt(LocalDateTime.now());
            zoneRepository.save(zone);
        });
    }

    public int cleanupExpiredZones() {
        List<Zone> expiredZones = zoneRepository.findExpiredZones(LocalDateTime.now(), Zone.ZoneStatus.expired);
        zoneRepository.deleteAll(expiredZones);
        return expiredZones.size();
    }

    public List<Zone> getDangerZones() {
        // Return all active zones that are NOT safety type (hazard, exclusion, monitoring, evacuation)
        return zoneRepository.findByTypeNotAndStatus(
            Zone.ZoneType.safety.name(), Zone.ZoneStatus.active);
    }

    public List<Zone> getRestrictedZones() {
        return zoneRepository.findByTypeAndStatus(
            Zone.ZoneType.exclusion.name(), Zone.ZoneStatus.active);
    }

    public long getActiveZoneCount() {
        return zoneRepository.count();
    }
}
