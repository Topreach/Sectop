package com.dangeremergence.repository;

import com.dangeremergence.model.CommunityLike;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface CommunityLikeRepository extends JpaRepository<CommunityLike, String> {

    Optional<CommunityLike> findByPostIdAndUserId(String postId, String userId);

    long countByPostId(String postId);

    void deleteByPostIdAndUserId(String postId, String userId);

    boolean existsByPostIdAndUserId(String postId, String userId);
}
