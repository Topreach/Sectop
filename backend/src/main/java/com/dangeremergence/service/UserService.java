package com.dangeremergence.service;

import com.dangeremergence.model.User;
import com.dangeremergence.repository.UserRepository;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Service
@Transactional
public class UserService {

    private static final Logger LOGGER = LoggerFactory.getLogger(UserService.class);

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JavaMailSender mailSender;

    @Autowired
    public UserService(UserRepository userRepository, PasswordEncoder passwordEncoder, JavaMailSender mailSender) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.mailSender = mailSender;
    }

    // -----------------------------------------------------------------------
    // Registration & Authentication
    // -----------------------------------------------------------------------

    public User registerUser(User user, String rawPassword) {
        if (user.getId() == null) {
            user.setId(UUID.randomUUID().toString());
        }
        user.setPasswordHash(passwordEncoder.encode(rawPassword));
        user.setLastSeen(LocalDateTime.now());
        user.setActive(true);
        return userRepository.save(user);
    }

    public Optional<User> authenticateUser(String email, String rawPassword) {
        Optional<User> userOpt = userRepository.findByEmail(email);
        if (userOpt.isPresent()) {
            User user = userOpt.get();
            if (user.getDeletedAt() != null) {
                return Optional.empty();
            }
            if (passwordEncoder.matches(rawPassword, user.getPasswordHash())) {
                user.setLastSeen(LocalDateTime.now());
                userRepository.save(user);
                return Optional.of(user);
            }
        }
        return Optional.empty();
    }

    // -----------------------------------------------------------------------
    // Lookup
    // -----------------------------------------------------------------------

    public Optional<User> getUserById(String id) {
        return userRepository.findById(id);
    }

    public Optional<User> getUserByEmail(String email) {
        return userRepository.findByEmail(email);
    }

    public Optional<User> getUserByPhone(String phone) {
        return userRepository.findByPhone(phone);
    }

    public List<User> getUsersByRole(User.UserRole role) {
        return userRepository.findByRole(role);
    }

    public List<User> getActiveUsersSince(LocalDateTime since) {
        return userRepository.findActiveUsersSince(since);
    }

    public List<User> getActiveResponders() {
        return userRepository.findActiveResponders(List.of(User.UserRole.responder, User.UserRole.coordinator));
    }

    public List<User> getUsersByIds(List<String> ids) {
        return userRepository.findByIds(ids);
    }

    /**
     * Check which phone numbers belong to registered users.
     * Used by the frontend Emergency Contacts screen to detect which
     * device contacts are already using the application.
     * Returns a map of phone -> user info (id, name) for matched numbers.
     */
    public Map<String, Map<String, String>> checkUsersByPhone(List<String> phoneNumbers) {
        Map<String, Map<String, String>> result = new java.util.HashMap<>();
        for (String phone : phoneNumbers) {
            if (phone == null || phone.isBlank()) continue;
            // Try exact match first
            Optional<User> userOpt = userRepository.findByPhone(phone);
            if (userOpt.isPresent() && userOpt.get().isActive()) {
                User user = userOpt.get();
                Map<String, String> info = new java.util.HashMap<>();
                info.put("id", user.getId());
                info.put("name", user.getName());
                result.put(phone, info);
            } else {
                // Try with country code normalization (remove +, spaces, etc.)
                String normalized = phone.replaceAll("[^0-9]", "");
                if (!normalized.equals(phone)) {
                    userOpt = userRepository.findByPhone(normalized);
                    if (userOpt.isPresent() && userOpt.get().isActive()) {
                        User user = userOpt.get();
                        Map<String, String> info = new java.util.HashMap<>();
                        info.put("id", user.getId());
                        info.put("name", user.getName());
                        result.put(phone, info);
                    }
                }
            }
        }
        return result;
    }

    // -----------------------------------------------------------------------
    // Update
    // -----------------------------------------------------------------------

    public User updateUser(User user) {
        user.setLastSeen(LocalDateTime.now());
        return userRepository.save(user);
    }

    public void updateLastSeen(String userId) {
        userRepository.findById(userId).ifPresent(user -> {
            user.setLastSeen(LocalDateTime.now());
            userRepository.save(user);
        });
    }

    public void deactivateUser(String userId) {
        userRepository.findById(userId).ifPresent(user -> {
            user.setActive(false);
            userRepository.save(user);
        });
    }

    // -----------------------------------------------------------------------
    // Existence checks
    // -----------------------------------------------------------------------

    public boolean emailExists(String email) {
        return userRepository.findByEmail(email).isPresent();
    }

    public boolean phoneExists(String phone) {
        return userRepository.findByPhone(phone).isPresent();
    }

    public long getActiveUserCount() {
        return userRepository.count();
    }

    // -----------------------------------------------------------------------
    // Password Reset
    // -----------------------------------------------------------------------

    /**
     * Generate a password-reset token, persist it, and send the reset email.
     * Returns true if the email was found and the email was sent.
     */
    public boolean requestPasswordReset(String email) {
        Optional<User> userOpt = userRepository.findByEmail(email);
        if (userOpt.isEmpty()) {
            return false;
        }
        User user = userOpt.get();
        if (user.getDeletedAt() != null) {
            return false;
        }

        String token = UUID.randomUUID().toString();
        user.setPasswordResetToken(token);
        user.setPasswordResetTokenExpiry(LocalDateTime.now().plusHours(1));
        userRepository.save(user);

        try {
            sendPasswordResetEmail(user, token);
            return true;
        } catch (Exception e) {
            LOGGER.error("Failed to send password reset email to {}: {}", email, e.getMessage());
            // Clear token so it doesn't leave dangling state
            user.setPasswordResetToken(null);
            user.setPasswordResetTokenExpiry(null);
            userRepository.save(user);
            return false;
        }
    }

    /**
     * Validate the reset token and update the password.
     */
    public boolean resetPassword(String token, String newPassword) {
        Optional<User> userOpt = userRepository.findByPasswordResetToken(token);
        if (userOpt.isEmpty()) {
            return false;
        }
        User user = userOpt.get();
        if (user.getPasswordResetTokenExpiry() == null || user.getPasswordResetTokenExpiry().isBefore(LocalDateTime.now())) {
            return false;
        }
        if (user.getDeletedAt() != null) {
            return false;
        }

        user.setPasswordHash(passwordEncoder.encode(newPassword));
        user.setPasswordResetToken(null);
        user.setPasswordResetTokenExpiry(null);
        userRepository.save(user);
        return true;
    }

    private void sendPasswordResetEmail(User user, String token) throws MessagingException {
        String resetUrl = "https://sectop.resultscaleai.com/reset-password?token=" + token;

        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
        helper.setTo(user.getEmail());
        helper.setSubject("Danger Emergence — Password Reset Request");
        helper.setText(
            "<html><body>" +
            "<h2>Password Reset</h2>" +
            "<p>Hello <strong>" + user.getName() + "</strong>,</p>" +
            "<p>We received a request to reset your password for the Danger Emergence System.</p>" +
            "<p>Click the link below to reset your password (valid for 1 hour):</p>" +
            "<p><a href=\"" + resetUrl + "\">Reset My Password</a></p>" +
            "<p>If you did not request this, please ignore this email.</p>" +
            "<p>Stay safe,<br/>Danger Emergence Team</p>" +
            "<hr/><p style='font-size:12px;color:#888;'>If the button above doesn't work, copy and paste this URL into your browser:<br/>" +
            resetUrl + "</p>" +
            "</body></html>",
            true /* isHtml */
        );
        mailSender.send(message);
    }

    // -----------------------------------------------------------------------
    // Account Deletion
    // -----------------------------------------------------------------------

    /**
     * Mark the user's account for deletion (30-day grace period).
     */
    public boolean requestAccountDeletion(String userId) {
        Optional<User> userOpt = userRepository.findById(userId);
        if (userOpt.isEmpty()) {
            return false;
        }
        User user = userOpt.get();
        if (user.getDeletedAt() != null) {
            return false; // already deleted
        }
        user.setDeletionRequestedAt(LocalDateTime.now());
        userRepository.save(user);
        return true;
    }

    /**
     * Cancel a pending deletion request.
     */
    public boolean cancelAccountDeletion(String userId) {
        Optional<User> userOpt = userRepository.findById(userId);
        if (userOpt.isEmpty()) {
            return false;
        }
        User user = userOpt.get();
        if (user.getDeletionRequestedAt() == null) {
            return false; // no pending deletion
        }
        user.setDeletionRequestedAt(null);
        userRepository.save(user);
        return true;
    }

    /**
     * Permanently delete (anonymize) the user's account.
     * Called after the grace period has elapsed.
     */
    public boolean deleteUserAccount(String userId) {
        Optional<User> userOpt = userRepository.findById(userId);
        if (userOpt.isEmpty()) {
            return false;
        }
        User user = userOpt.get();
        if (user.getDeletedAt() != null) {
            return false; // already deleted
        }

        // Anonymize personally identifiable information
        user.setName("Deleted User");
        user.setEmail("deleted-" + user.getId() + "@anon.dangeremergence.com");
        user.setPhone(null);
        user.setPasswordHash(null);
        user.setPublicKey(null);
        user.setEmergencyContacts(null);
        user.setMedicalInfo(null);
        user.setActive(false);
        user.setDeletedAt(LocalDateTime.now());
        user.setDeletionRequestedAt(null);
        user.setPasswordResetToken(null);
        user.setPasswordResetTokenExpiry(null);
        userRepository.save(user);
        return true;
    }

    /**
     * Scheduled task that processes accounts whose 30-day grace period has expired.
     * Runs daily at 3 AM.
     */
    @Scheduled(cron = "${scheduling.cleanup.deletion-cron:0 0 3 * * ?}")
    public void processPendingDeletions() {
        LocalDateTime cutoff = LocalDateTime.now().minusDays(30);
        List<User> pending = userRepository.findPendingDeletions(cutoff);
        for (User user : pending) {
            try {
                deleteUserAccount(user.getId());
                LOGGER.info("Processed pending deletion for user {}", user.getId());
            } catch (Exception e) {
                LOGGER.error("Failed to process deletion for user {}: {}", user.getId(), e.getMessage());
            }
        }
    }
}
