package com.dangeremergence.repository;

import com.dangeremergence.model.CommunityComment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CommunityCommentRepository extends JpaRepository<CommunityComment, String> {

    List<CommunityComment> findByPostIdOrderByCreatedAtAsc(String postId);

    long countByPostId(String postId);

    void deleteByIdAndUserId(String id, String userId);
}
