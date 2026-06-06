package com.dangeremergence.repository;

import com.dangeremergence.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, String> {

    Optional<User> findByEmail(String email);

    Optional<User> findByPhone(String phone);

    List<User> findByRole(User.UserRole role);

    @Query("SELECT u FROM User u WHERE u.lastSeen > :since")
    List<User> findActiveUsersSince(@Param("since") LocalDateTime since);

    @Query("SELECT u FROM User u WHERE u.active = true AND u.role IN :roles")
    List<User> findActiveResponders(@Param("roles") List<User.UserRole> roles);

    @Query("SELECT u FROM User u WHERE u.id IN :ids")
    List<User> findByIds(@Param("ids") List<String> ids);

    long countByRole(User.UserRole role);
}
