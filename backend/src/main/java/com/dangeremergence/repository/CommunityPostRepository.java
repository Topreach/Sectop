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

    @Query("SELECT p FROM CommunityPost p WHERE p.status = 'active' " +
           "AND (:latitude IS NULL OR :longitude IS NULL OR " +
           "function('sqrt', function('pow', (p.latitude - :latitude) * 111.32, 2) + " +
           "function('pow', (p.longitude - :longitude) * 111.32 * function('cos', function('radians', :latitude)), 2)) < :radiusKm) " +
           "ORDER BY p.createdAt DESC")
    Page<CommunityPost> findNearby(
            @Param("latitude") Double latitude,
            @Param("longitude") Double longitude,
            @Param("radiusKm") Double radiusKm,
            Pageable pageable);

    long countByStatus(PostStatus status);
}
