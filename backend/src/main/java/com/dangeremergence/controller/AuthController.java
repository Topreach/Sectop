package com.dangeremergence.controller;

import com.dangeremergence.model.User;
import com.dangeremergence.service.UserService;
import com.dangeremergence.service.EmergencyBypassService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private static final Logger LOGGER = LoggerFactory.getLogger(AuthController.class);

    // Simple in-memory rate limit tracking: IP -> timestamps (ms)
    private static final ConcurrentHashMap<String, CopyOnWriteArrayList<Long>> bypassRequests = new ConcurrentHashMap<>();
    private static final int BYPASS_LIMIT = 5; // max per window
    private static final long BYPASS_WINDOW_MS = 60L * 60L * 1000L; // 1 hour

    private final UserService userService;
    private final com.dangeremergence.config.JwtUtil jwtUtil;

    private final EmergencyBypassService emergencyBypassService;

    @Autowired
    public AuthController(UserService userService, com.dangeremergence.config.JwtUtil jwtUtil, EmergencyBypassService emergencyBypassService) {
        this.userService = userService;
        this.jwtUtil = jwtUtil;
        this.emergencyBypassService = emergencyBypassService;
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody RegisterRequest request) {
        // Validate required fields
        if (request.getName() == null || request.getName().isBlank()) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Name is required");
            return ResponseEntity.badRequest().body(error);
        }
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Email is required");
            return ResponseEntity.badRequest().body(error);
        }
        if (request.getPassword() == null || request.getPassword().isBlank()) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Password is required");
            return ResponseEntity.badRequest().body(error);
        }

        if (userService.emailExists(request.getEmail())) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Email already registered");
            return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
        }

        if (request.getPhone() != null && !request.getPhone().isBlank() && userService.phoneExists(request.getPhone())) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Phone number already registered");
            return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
        }

        User user = new User();
        user.setName(request.getName());
        user.setEmail(request.getEmail());
        user.setPhone(request.getPhone());
        user.setRole(request.getRole() != null ? request.getRole() : User.UserRole.citizen);

        User savedUser = userService.registerUser(user, request.getPassword());

        Map<String, Object> response = new HashMap<>();
        response.put("userId", savedUser.getId());
        response.put("name", savedUser.getName());
        response.put("email", savedUser.getEmail());
        response.put("role", savedUser.getRole());
        response.put("message", "Registration successful");
        // Issue JWT for the new user
        try {
            String token = jwtUtil.generateToken(savedUser.getId(), savedUser.getEmail(), savedUser.getRole().name());
            response.put("token", token);
        } catch (Exception ignored) {}

        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        Optional<User> userOpt = userService.authenticateUser(request.getEmail(), request.getPassword());

        if (userOpt.isPresent()) {
            User user = userOpt.get();
            Map<String, Object> response = new HashMap<>();
            response.put("userId", user.getId());
            response.put("name", user.getName());
            response.put("email", user.getEmail());
            response.put("phone", user.getPhone());
            response.put("role", user.getRole());
            response.put("publicKey", user.getPublicKey());
            response.put("message", "Login successful");
            // Issue JWT
            try {
                String token = jwtUtil.generateToken(user.getId(), user.getEmail(), user.getRole().name());
                response.put("token", token);
            } catch (Exception ignored) {}
            return ResponseEntity.ok(response);
        }

        Map<String, String> error = new HashMap<>();
        error.put("error", "Invalid email or password");
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(error);
    }

    @PostMapping("/emergency-bypass")
    public ResponseEntity<?> emergencyBypass(@RequestBody EmergencyBypassRequest request,
                                             @RequestHeader(value = "X-EMERGENCY-AUTH", required = false) String emergencyAuth,
                                             HttpServletRequest httpRequest) {
        // Emergency bypass: protected by optional API key or limited-rate per IP; issues short-lived emergency JWT
        String configuredKey = System.getenv("EMERGENCY_BYPASS_KEY");
        String clientIp = httpRequest.getRemoteAddr();

        String method = "rate_limit";
        // If a bypass key is configured, require it
        if (configuredKey != null && !configuredKey.isBlank()) {
            method = "key";
            if (emergencyAuth == null || !configuredKey.equals(emergencyAuth)) {
                LOGGER.warn("Emergency bypass attempt with invalid key from {}", clientIp);
                emergencyBypassService.record(null, request.getPhone(), clientIp, method, false, false);
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Invalid emergency auth"));
            }
        } else {
            // Rate limit by IP
            long now = System.currentTimeMillis();
            bypassRequests.putIfAbsent(clientIp, new CopyOnWriteArrayList<>());
            var timestamps = bypassRequests.get(clientIp);
            // Remove stale entries
            timestamps.removeIf(ts -> ts < now - BYPASS_WINDOW_MS);
            if (timestamps.size() >= BYPASS_LIMIT) {
                LOGGER.warn("Emergency bypass rate limit exceeded from {}", clientIp);
                return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS).body(Map.of("error", "Rate limit exceeded"));
            }
            timestamps.add(now);
        }

        // Create emergency session and issue short-lived token
        String sessionId = "emergency_" + System.currentTimeMillis();
        Map<String, Object> response = new HashMap<>();
        response.put("sessionId", sessionId);
        response.put("name", request.getName() != null ? request.getName() : "Emergency User");
        response.put("phone", request.getPhone());
        response.put("role", "citizen");
        response.put("emergencyMode", true);

        boolean tokenIssued = false;
        try {
            // 10 minute token
            long tenMinutes = 10L * 60L * 1000L;
            String token = jwtUtil.generateTokenWithExpiry(sessionId, request.getPhone() != null ? request.getPhone() : "", "citizen", tenMinutes, true);
            response.put("token", token);
            tokenIssued = true;
        } catch (Exception e) {
            LOGGER.error("Failed to issue emergency token for {}: {}", clientIp, e.getMessage());
        }

        LOGGER.info("Emergency bypass granted for {} (ip={})", request.getPhone(), clientIp);
        // persist audit
        try {
            emergencyBypassService.record(sessionId, request.getPhone(), clientIp, method, true, tokenIssued);
        } catch (Exception e) {
            LOGGER.error("Failed to persist emergency bypass audit: {}", e.getMessage());
        }
        response.put("message", "Emergency access granted");
        return ResponseEntity.ok(response);
    }

    // -----------------------------------------------------------------------
    // Password Reset
    // -----------------------------------------------------------------------

    @PostMapping("/forgot-password")
    public ResponseEntity<?> forgotPassword(@RequestBody ForgotPasswordRequest request) {
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Email is required"));
        }

        boolean sent = userService.requestPasswordReset(request.getEmail().trim().toLowerCase());
        // Always return 200 to avoid email enumeration
        Map<String, Object> response = new HashMap<>();
        response.put("message", "If the email exists, a password reset link has been sent.");
        return ResponseEntity.ok(response);
    }

    @PostMapping("/reset-password")
    public ResponseEntity<?> resetPassword(@RequestBody ResetPasswordRequest request) {
        if (request.getToken() == null || request.getToken().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Token is required"));
        }
        if (request.getNewPassword() == null || request.getNewPassword().length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Password must be at least 6 characters"));
        }

        boolean success = userService.resetPassword(request.getToken().trim(), request.getNewPassword());
        if (success) {
            return ResponseEntity.ok(Map.of("message", "Password reset successful"));
        }
        return ResponseEntity.badRequest().body(Map.of("error", "Invalid or expired reset token"));
    }

    // -----------------------------------------------------------------------
    // Account Deletion
    // -----------------------------------------------------------------------

    @PostMapping("/account/deletion-request")
    public ResponseEntity<?> requestDeletion(@RequestHeader("X-User-Id") String userId) {
        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "User ID is required"));
        }
        boolean success = userService.requestAccountDeletion(userId);
        if (success) {
            return ResponseEntity.ok(Map.of(
                "message", "Account deletion requested. Your account will be permanently deleted after 30 days.",
                "gracePeriodDays", 30
            ));
        }
        return ResponseEntity.badRequest().body(Map.of("error", "Unable to process deletion request"));
    }

    @PostMapping("/account/cancel-deletion")
    public ResponseEntity<?> cancelDeletion(@RequestHeader("X-User-Id") String userId) {
        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "User ID is required"));
        }
        boolean success = userService.cancelAccountDeletion(userId);
        if (success) {
            return ResponseEntity.ok(Map.of("message", "Deletion request cancelled"));
        }
        return ResponseEntity.badRequest().body(Map.of("error", "No pending deletion request found"));
    }

    @DeleteMapping("/account")
    public ResponseEntity<?> deleteAccount(@RequestHeader("X-User-Id") String userId) {
        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "User ID is required"));
        }
        boolean success = userService.deleteUserAccount(userId);
        if (success) {
            return ResponseEntity.ok(Map.of("message", "Account permanently deleted"));
        }
        return ResponseEntity.badRequest().body(Map.of("error", "Unable to delete account"));
    }

    // -----------------------------------------------------------------------
    // User Profile
    // -----------------------------------------------------------------------

    @GetMapping("/users/{userId}")
    public ResponseEntity<?> getUser(@PathVariable String userId) {
        Optional<User> userOpt = userService.getUserById(userId);
        if (userOpt.isPresent()) {
            User user = userOpt.get();
            Map<String, Object> response = new HashMap<>();
            response.put("userId", user.getId());
            response.put("name", user.getName());
            response.put("email", user.getEmail());
            response.put("phone", user.getPhone());
            response.put("role", user.getRole());
            response.put("isActive", user.isActive());
            response.put("lastSeen", user.getLastSeen());
            return ResponseEntity.ok(response);
        }
        Map<String, String> error = new HashMap<>();
        error.put("error", "User not found");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @PutMapping("/users/{userId}")
    public ResponseEntity<?> updateUser(@PathVariable String userId, @RequestBody UpdateUserRequest request) {
        Optional<User> userOpt = userService.getUserById(userId);
        if (userOpt.isPresent()) {
            User user = userOpt.get();
            if (request.getName() != null) user.setName(request.getName());
            if (request.getPhone() != null) user.setPhone(request.getPhone());
            if (request.getEmergencyContacts() != null) user.setEmergencyContacts(request.getEmergencyContacts());
            if (request.getMedicalInfo() != null) user.setMedicalInfo(request.getMedicalInfo());
            if (request.getPublicKey() != null) user.setPublicKey(request.getPublicKey());
            if (request.getRole() != null) user.setRole(request.getRole());
            if (request.getFcmToken() != null) user.setFcmToken(request.getFcmToken());
            if (request.getLatitude() != null) user.setLatitude(request.getLatitude());
            if (request.getLongitude() != null) user.setLongitude(request.getLongitude());

            User updatedUser = userService.updateUser(user);
            Map<String, Object> response = new HashMap<>();
            response.put("userId", updatedUser.getId());
            response.put("name", updatedUser.getName());
            response.put("role", updatedUser.getRole());
            response.put("message", "Profile updated successfully");
            return ResponseEntity.ok(response);
        }
        Map<String, String> error = new HashMap<>();
        error.put("error", "User not found");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    /**
     * Dedicated endpoint for FCM token registration.
     * Called by the mobile app when the device token changes.
     */
    @PostMapping("/users/{userId}/fcm-token")
    public ResponseEntity<?> registerFcmToken(@PathVariable String userId, @RequestBody Map<String, String> body) {
        String fcmToken = body.get("fcmToken");
        if (fcmToken == null || fcmToken.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "fcmToken is required"));
        }
        Optional<User> userOpt = userService.getUserById(userId);
        if (userOpt.isPresent()) {
            User user = userOpt.get();
            user.setFcmToken(fcmToken);
            userService.updateUser(user);
            log.info("FCM token registered for user: {}", userId);
            return ResponseEntity.ok(Map.of("message", "FCM token registered successfully"));
        }
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "User not found"));
    }

    @GetMapping("/responders")
    public ResponseEntity<?> getActiveResponders() {
        var responders = userService.getActiveResponders();
        return ResponseEntity.ok(responders);
    }

    /**
     * Check which phone numbers belong to registered users of the application.
     * Used by the frontend Emergency Contacts screen to detect which device
     * contacts are already using Sectop, so the user can see them and share
     * the app with non-users.
     * <p>
     * Request body: { "phones": ["+2348012345678", "+2348098765432", ...] }
     * Response: { "results": { "+2348012345678": { "id": "user-123", "name": "John" }, ... } }
     */
    @PostMapping("/check-users")
    public ResponseEntity<?> checkUsersByPhone(@RequestBody Map<String, List<String>> body) {
        List<String> phones = body.get("phones");
        if (phones == null || phones.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "phones list is required"));
        }
        // Limit to reasonable batch size
        if (phones.size() > 100) {
            phones = phones.subList(0, 100);
        }
        Map<String, Map<String, String>> results = userService.checkUsersByPhone(phones);
        return ResponseEntity.ok(Map.of("results", results));
    }

    // -----------------------------------------------------------------------
    // Request DTOs
    // -----------------------------------------------------------------------

    public static class RegisterRequest {
        private String name;
        private String email;
        private String phone;
        private String password;
        private User.UserRole role;

        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getEmail() { return email; }
        public void setEmail(String email) { this.email = email; }
        public String getPhone() { return phone; }
        public void setPhone(String phone) { this.phone = phone; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
        public User.UserRole getRole() { return role; }
        public void setRole(User.UserRole role) { this.role = role; }
    }

    public static class LoginRequest {
        private String email;
        private String password;

        public String getEmail() { return email; }
        public void setEmail(String email) { this.email = email; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
    }

    public static class EmergencyBypassRequest {
        private String name;
        private String phone;
        private String location;

        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getPhone() { return phone; }
        public void setPhone(String phone) { this.phone = phone; }
        public String getLocation() { return location; }
        public void setLocation(String location) { this.location = location; }
    }

    public static class UpdateUserRequest {
        private String name;
        private String phone;
        private String emergencyContacts;
        private String medicalInfo;
        private String publicKey;
        private User.UserRole role;
        private String fcmToken;
        private Double latitude;
        private Double longitude;

        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getPhone() { return phone; }
        public void setPhone(String phone) { this.phone = phone; }
        public String getEmergencyContacts() { return emergencyContacts; }
        public void setEmergencyContacts(String emergencyContacts) { this.emergencyContacts = emergencyContacts; }
        public String getMedicalInfo() { return medicalInfo; }
        public void setMedicalInfo(String medicalInfo) { this.medicalInfo = medicalInfo; }
        public String getPublicKey() { return publicKey; }
        public void setPublicKey(String publicKey) { this.publicKey = publicKey; }
        public User.UserRole getRole() { return role; }
        public void setRole(User.UserRole role) { this.role = role; }
        public String getFcmToken() { return fcmToken; }
        public void setFcmToken(String fcmToken) { this.fcmToken = fcmToken; }
        public Double getLatitude() { return latitude; }
        public void setLatitude(Double latitude) { this.latitude = latitude; }
        public Double getLongitude() { return longitude; }
        public void setLongitude(Double longitude) { this.longitude = longitude; }
    }

    public static class ForgotPasswordRequest {
        private String email;

        public String getEmail() { return email; }
        public void setEmail(String email) { this.email = email; }
    }

    public static class ResetPasswordRequest {
        private String token;
        private String newPassword;

        public String getToken() { return token; }
        public void setToken(String token) { this.token = token; }
        public String getNewPassword() { return newPassword; }
        public void setNewPassword(String newPassword) { this.newPassword = newPassword; }
    }
}
