package com.dangeremergence.controller;

import com.dangeremergence.model.User;
import com.dangeremergence.service.UserService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final UserService userService;

    @Autowired
    public AuthController(UserService userService) {
        this.userService = userService;
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody RegisterRequest request) {
        if (userService.emailExists(request.getEmail())) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Email already registered");
            return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
        }

        if (userService.phoneExists(request.getPhone())) {
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
            return ResponseEntity.ok(response);
        }

        Map<String, String> error = new HashMap<>();
        error.put("error", "Invalid email or password");
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(error);
    }

    @PostMapping("/emergency-bypass")
    public ResponseEntity<?> emergencyBypass(@RequestBody EmergencyBypassRequest request) {
        // Emergency bypass creates a temporary session without full authentication
        Map<String, Object> response = new HashMap<>();
        response.put("sessionId", "emergency_" + System.currentTimeMillis());
        response.put("name", request.getName() != null ? request.getName() : "Emergency User");
        response.put("phone", request.getPhone());
        response.put("role", "citizen");
        response.put("emergencyMode", true);
        response.put("message", "Emergency access granted");
        return ResponseEntity.ok(response);
    }

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

            User updatedUser = userService.updateUser(user);
            Map<String, Object> response = new HashMap<>();
            response.put("userId", updatedUser.getId());
            response.put("name", updatedUser.getName());
            response.put("message", "Profile updated successfully");
            return ResponseEntity.ok(response);
        }
        Map<String, String> error = new HashMap<>();
        error.put("error", "User not found");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @GetMapping("/responders")
    public ResponseEntity<?> getActiveResponders() {
        var responders = userService.getActiveResponders();
        return ResponseEntity.ok(responders);
    }

    // Request DTOs
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
    }
}
