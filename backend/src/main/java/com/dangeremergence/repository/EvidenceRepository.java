package com.dangeremergence.repository;

import com.dangeremergence.model.Evidence;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Repository for Evidence entities.
 */
@Repository
public interface EvidenceRepository extends JpaRepository<Evidence, String> {

    /** Find all evidence for a parent entity (alert, incident, or tip). */
    List<Evidence> findByParentIdOrderByCapturedAtDesc(String parentId);

    /** Find evidence by parent type (e.g., all evidence for alerts). */
    List<Evidence> findByParentTypeOrderByCapturedAtDesc(String parentType);

    /** Find evidence by type (photo, video, audio). */
    List<Evidence> findByEvidenceTypeOrderByCapturedAtDesc(String evidenceType);

    /** Count evidence for a parent. */
    long countByParentId(String parentId);

    /** Delete all evidence for a parent. */
    void deleteByParentId(String parentId);
}
