package com.dangeremergence.repository;

import com.dangeremergence.model.CommunityFavorite;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CommunityFavoriteRepository extends JpaRepository<CommunityFavorite, String> {

    Optional<CommunityFavorite> findByPostIdAndUserId(String postId, String userId);

    List<CommunityFavorite> findByUserIdOrderByCreatedAtDesc(String userId);

    long countByPostId(String postId);

    boolean existsByPostIdAndUserId(String postId, String userId);

    void deleteByPostIdAndUserId(String postId, String userId);
}
