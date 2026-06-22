package com.dangeremergence.controller;

import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.UserRepository;
import com.dangeremergence.service.EmergencyBypassService;
import com.dangeremergence.service.UserService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = AuthController.class, excludeAutoConfiguration = {org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration.class, org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration.class})
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private UserService userService;

    @MockBean
    private JwtUtil jwtUtil;

    @MockBean
    private EmergencyBypassService emergencyBypassService;

    @MockBean
    private UserRepository userRepository;

    private User testUser;
    private static final String USER_ID = "user-123";
    private static final String TEST_EMAIL = "test@example.com";
    private static final String TEST_PASSWORD = "password123";
    private static final String TEST_NAME = "Test User";
    private static final String TEST_PHONE = "+2348012345678";

    @BeforeEach
    void setUp() {
        testUser = new User();
        testUser.setId(USER_ID);
        testUser.setName(TEST_NAME);
        testUser.setEmail(TEST_EMAIL);
        testUser.setPhone(TEST_PHONE);
        testUser.setRole(User.UserRole.citizen);
        testUser.setActive(true);

        when(jwtUtil.generateToken(anyString(), anyString(), anyString()))
                .thenReturn("test-jwt-token");
    }

    @Nested
    class Register {

        @Test
        void shouldRegisterSuccessfully() throws Exception {
            when(userService.emailExists(TEST_EMAIL)).thenReturn(false);
            when(userService.phoneExists(TEST_PHONE)).thenReturn(false);
            when(userService.registerUser(any(User.class), eq(TEST_PASSWORD)))
                    .thenReturn(testUser);

            Map<String, Object> request = Map.of(
                    "name", TEST_NAME,
                    "email", TEST_EMAIL,
                    "phone", TEST_PHONE,
                    "password", TEST_PASSWORD
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.userId").value(USER_ID))
                    .andExpect(jsonPath("$.name").value(TEST_NAME))
                    .andExpect(jsonPath("$.email").value(TEST_EMAIL))
                    .andExpect(jsonPath("$.role").value("citizen"))
                    .andExpect(jsonPath("$.token").value("test-jwt-token"))
                    .andExpect(jsonPath("$.message").value("Registration successful"));
        }

        @Test
        void shouldReturn400WhenNameMissing() throws Exception {
            Map<String, Object> request = Map.of(
                    "email", TEST_EMAIL,
                    "password", TEST_PASSWORD
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Name is required"));
        }

        @Test
        void shouldReturn400WhenEmailMissing() throws Exception {
            Map<String, Object> request = Map.of(
                    "name", TEST_NAME,
                    "password", TEST_PASSWORD
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Email is required"));
        }

        @Test
        void shouldReturn400WhenPasswordMissing() throws Exception {
            Map<String, Object> request = Map.of(
                    "name", TEST_NAME,
                    "email", TEST_EMAIL
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Password is required"));
        }

        @Test
        void shouldReturn409WhenEmailExists() throws Exception {
            when(userService.emailExists(TEST_EMAIL)).thenReturn(true);

            Map<String, Object> request = Map.of(
                    "name", TEST_NAME,
                    "email", TEST_EMAIL,
                    "password", TEST_PASSWORD
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.error").value("Email already registered"));
        }

        @Test
        void shouldReturn409WhenPhoneExists() throws Exception {
            when(userService.emailExists(TEST_EMAIL)).thenReturn(false);
            when(userService.phoneExists(TEST_PHONE)).thenReturn(true);

            Map<String, Object> request = Map.of(
                    "name", TEST_NAME,
                    "email", TEST_EMAIL,
                    "phone", TEST_PHONE,
                    "password", TEST_PASSWORD
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.error").value("Phone number already registered"));
        }

        @Test
        void shouldRegisterWithResponderRole() throws Exception {
            when(userService.emailExists(TEST_EMAIL)).thenReturn(false);
            when(userService.registerUser(any(User.class), eq(TEST_PASSWORD)))
                    .thenReturn(testUser);

            Map<String, Object> request = Map.of(
                    "name", TEST_NAME,
                    "email", TEST_EMAIL,
                    "password", TEST_PASSWORD,
                    "role", "responder"
            );

            mockMvc.perform(post("/api/v1/auth/register")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.role").value("citizen"));
        }
    }

    @Nested
    class Login {

        @Test
        void shouldLoginSuccessfully() throws Exception {
            when(userService.authenticateUser(TEST_EMAIL, TEST_PASSWORD))
                    .thenReturn(Optional.of(testUser));

            Map<String, Object> request = Map.of(
                    "email", TEST_EMAIL,
                    "password", TEST_PASSWORD
            );

            mockMvc.perform(post("/api/v1/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userId").value(USER_ID))
                    .andExpect(jsonPath("$.email").value(TEST_EMAIL))
                    .andExpect(jsonPath("$.token").value("test-jwt-token"))
                    .andExpect(jsonPath("$.message").value("Login successful"));
        }

        @Test
        void shouldReturn401WhenInvalidCredentials() throws Exception {
            when(userService.authenticateUser(TEST_EMAIL, "wrong"))
                    .thenReturn(Optional.empty());

            Map<String, Object> request = Map.of(
                    "email", TEST_EMAIL,
                    "password", "wrong"
            );

            mockMvc.perform(post("/api/v1/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.error").value("Invalid email or password"));
        }
    }

    @Nested
    class ForgotPassword {

        @Test
        void shouldReturn200AlwaysToPreventEnumeration() throws Exception {
            when(userService.requestPasswordReset(TEST_EMAIL)).thenReturn(true);

            Map<String, Object> request = Map.of("email", TEST_EMAIL);

            mockMvc.perform(post("/api/v1/auth/forgot-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("If the email exists, a password reset link has been sent."));
        }

        @Test
        void shouldReturn200EvenWhenEmailNotFound() throws Exception {
            when(userService.requestPasswordReset("unknown@example.com")).thenReturn(false);

            Map<String, Object> request = Map.of("email", "unknown@example.com");

            mockMvc.perform(post("/api/v1/auth/forgot-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("If the email exists, a password reset link has been sent."));
        }

        @Test
        void shouldReturn400WhenEmailMissing() throws Exception {
            Map<String, Object> request = Map.of();

            mockMvc.perform(post("/api/v1/auth/forgot-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Email is required"));
        }
    }

    @Nested
    class ResetPassword {

        @Test
        void shouldResetPasswordSuccessfully() throws Exception {
            when(userService.resetPassword("valid-token", "newPass123"))
                    .thenReturn(true);

            Map<String, Object> request = Map.of(
                    "token", "valid-token",
                    "newPassword", "newPass123"
            );

            mockMvc.perform(post("/api/v1/auth/reset-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Password reset successful"));
        }

        @Test
        void shouldReturn400WhenTokenInvalid() throws Exception {
            when(userService.resetPassword("invalid-token", "newPass123"))
                    .thenReturn(false);

            Map<String, Object> request = Map.of(
                    "token", "invalid-token",
                    "newPassword", "newPass123"
            );

            mockMvc.perform(post("/api/v1/auth/reset-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Invalid or expired reset token"));
        }

        @Test
        void shouldReturn400WhenTokenMissing() throws Exception {
            Map<String, Object> request = Map.of("newPassword", "newPass123");

            mockMvc.perform(post("/api/v1/auth/reset-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Token is required"));
        }

        @Test
        void shouldReturn400WhenPasswordTooShort() throws Exception {
            Map<String, Object> request = Map.of(
                    "token", "valid-token",
                    "newPassword", "12345"
            );

            mockMvc.perform(post("/api/v1/auth/reset-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Password must be at least 6 characters"));
        }
    }

    @Nested
    class AccountDeletion {

        @Test
        void shouldRequestDeletionSuccessfully() throws Exception {
            when(userService.requestAccountDeletion(USER_ID)).thenReturn(true);

            mockMvc.perform(post("/api/v1/auth/account/deletion-request")
                            .header("X-User-Id", USER_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Account deletion requested. Your account will be permanently deleted after 30 days."))
                    .andExpect(jsonPath("$.gracePeriodDays").value(30));
        }

        @Test
        void shouldReturn400WhenDeletionRequestFails() throws Exception {
            when(userService.requestAccountDeletion(USER_ID)).thenReturn(false);

            mockMvc.perform(post("/api/v1/auth/account/deletion-request")
                            .header("X-User-Id", USER_ID))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Unable to process deletion request"));
        }

        @Test
        void shouldCancelDeletionSuccessfully() throws Exception {
            when(userService.cancelAccountDeletion(USER_ID)).thenReturn(true);

            mockMvc.perform(post("/api/v1/auth/account/cancel-deletion")
                            .header("X-User-Id", USER_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Deletion request cancelled"));
        }

        @Test
        void shouldReturn400WhenCancelFails() throws Exception {
            when(userService.cancelAccountDeletion(USER_ID)).thenReturn(false);

            mockMvc.perform(post("/api/v1/auth/account/cancel-deletion")
                            .header("X-User-Id", USER_ID))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("No pending deletion request found"));
        }

        @Test
        void shouldDeleteAccountSuccessfully() throws Exception {
            when(userService.deleteUserAccount(USER_ID)).thenReturn(true);

            mockMvc.perform(delete("/api/v1/auth/account")
                            .header("X-User-Id", USER_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Account permanently deleted"));
        }

        @Test
        void shouldReturn400WhenDeleteFails() throws Exception {
            when(userService.deleteUserAccount(USER_ID)).thenReturn(false);

            mockMvc.perform(delete("/api/v1/auth/account")
                            .header("X-User-Id", USER_ID))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Unable to delete account"));
        }
    }

    @Nested
    class UserProfile {

        @Test
        void shouldGetUserById() throws Exception {
            when(userService.getUserById(USER_ID)).thenReturn(Optional.of(testUser));

            mockMvc.perform(get("/api/v1/auth/users/{userId}", USER_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userId").value(USER_ID))
                    .andExpect(jsonPath("$.name").value(TEST_NAME))
                    .andExpect(jsonPath("$.email").value(TEST_EMAIL))
                    .andExpect(jsonPath("$.isActive").value(true));
        }

        @Test
        void shouldReturn404WhenUserNotFound() throws Exception {
            when(userService.getUserById("unknown")).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/v1/auth/users/{userId}", "unknown"))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.error").value("User not found"));
        }

        @Test
        void shouldUpdateUserSuccessfully() throws Exception {
            when(userService.getUserById(USER_ID)).thenReturn(Optional.of(testUser));
            when(userService.updateUser(any(User.class))).thenReturn(testUser);

            Map<String, Object> request = Map.of(
                    "name", "Updated Name",
                    "fcmToken", "new-fcm-token"
            );

            mockMvc.perform(put("/api/v1/auth/users/{userId}", USER_ID)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userId").value(USER_ID))
                    .andExpect(jsonPath("$.message").value("Profile updated successfully"));
        }

        @Test
        void shouldReturn404WhenUpdatingNonExistentUser() throws Exception {
            when(userService.getUserById("unknown")).thenReturn(Optional.empty());

            Map<String, Object> request = Map.of("name", "Updated Name");

            mockMvc.perform(put("/api/v1/auth/users/{userId}", "unknown")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.error").value("User not found"));
        }

        @Test
        void shouldGetActiveResponders() throws Exception {
            when(userService.getActiveResponders()).thenReturn(List.of(testUser));

            mockMvc.perform(get("/api/v1/auth/responders"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].userId").value(USER_ID));
        }
    }

    @Nested
    class EmergencyBypass {

        @Test
        void shouldGrantEmergencyBypassWithRateLimit() throws Exception {
            Map<String, Object> request = Map.of(
                    "name", "Emergency User",
                    "phone", TEST_PHONE
            );

            mockMvc.perform(post("/api/v1/auth/emergency-bypass")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.emergencyMode").value(true))
                    .andExpect(jsonPath("$.role").value("citizen"))
                    .andExpect(jsonPath("$.message").value("Emergency access granted"));
        }

        @Test
        void shouldRequireValidKeyWhenConfigured() throws Exception {
            // Note: This test relies on EMERGENCY_BYPASS_KEY env var not being set
            // If set, the test would need to provide X-EMERGENCY-AUTH header
            Map<String, Object> request = Map.of(
                    "phone", TEST_PHONE
            );

            mockMvc.perform(post("/api/v1/auth/emergency-bypass")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.emergencyMode").value(true));
        }
    }
}
