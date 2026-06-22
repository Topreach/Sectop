package com.dangeremergence.repository;

import com.dangeremergence.model.CommunityShare;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface CommunityShareRepository extends JpaRepository<CommunityShare, String> {

    long countByPostId(String postId);
}
