package com.dangeremergence.repository;

import com.dangeremergence.model.CommunityPost;
import com.dangeremergence.model.CommunityPost.PostStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CommunityPostRepository extends JpaRepository<CommunityPost, String> {

    Page<CommunityPost> findByStatusOrderByCreatedAtDesc(PostStatus status, Pageable pageable);

    List<CommunityPost> findByUserIdAndStatusOrderByCreatedAtDesc(String userId, PostStatus status);

    @Query(value = "SELECT * FROM community_posts p WHERE p.status = 'active' " +
           "AND (:latitude IS NULL OR :longitude IS NULL OR " +
           "SQRT(POW((p.latitude - :latitude) * 111.32, 2) + " +
           "POW((p.longitude - :longitude) * 111.32 * COS(RADIANS(:latitude)), 2)) < :radiusKm) " +
           "ORDER BY p.created_at DESC",
           countQuery = "SELECT COUNT(*) FROM community_posts p WHERE p.status = 'active' " +
                        "AND (:latitude IS NULL OR :longitude IS NULL OR " +
                        "SQRT(POW((p.latitude - :latitude) * 111.32, 2) + " +
                        "POW((p.longitude - :longitude) * 111.32 * COS(RADIANS(:latitude)), 2)) < :radiusKm)",
           nativeQuery = true)
    Page<CommunityPost> findNearby(
            @Param("latitude") Double latitude,
            @Param("longitude") Double longitude,
            @Param("radiusKm") Double radiusKm,
            Pageable pageable);

    long countByStatus(PostStatus status);
}
