package com.dangeremergence.service;

import com.dangeremergence.model.User;
import com.dangeremergence.repository.UserRepository;
import jakarta.mail.internet.MimeMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("UserService Unit Tests")
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private JavaMailSender mailSender;

    @Mock
    private MimeMessage mimeMessage;

    @InjectMocks
    private UserService userService;

    @Captor
    private ArgumentCaptor<User> userCaptor;

    private User testUser;
    private final String userId = "user-123";
    private final String email = "test@example.com";
    private final String rawPassword = "SecurePass123!";
    private final String encodedPassword = "$2a$10$encodedHash";

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .id(userId)
                .name("Test User")
                .email(email)
                .passwordHash(encodedPassword)
                .role(User.UserRole.citizen)
                .active(true)
                .phone("+2348012345678")
                .build();
    }

    @Nested
    @DisplayName("registerUser()")
    class RegisterUser {

        @Test
        @DisplayName("should register user with provided ID and encode password")
        void shouldRegisterUserWithProvidedId() {
            User newUser = User.builder()
                    .id(userId)
                    .name("New User")
                    .email("new@example.com")
                    .build();

            when(passwordEncoder.encode(rawPassword)).thenReturn(encodedPassword);
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            User result = userService.registerUser(newUser, rawPassword);

            verify(passwordEncoder).encode(rawPassword);
            verify(userRepository).save(userCaptor.capture());
            User saved = userCaptor.getValue();
            assertThat(saved.getId()).isEqualTo(userId);
            assertThat(saved.getPasswordHash()).isEqualTo(encodedPassword);
            assertThat(saved.getEmail()).isEqualTo("new@example.com");
            assertThat(result).isSameAs(saved);
        }

        @Test
        @DisplayName("should generate UUID when user ID is null")
        void shouldGenerateUuidWhenIdIsNull() {
            User newUser = User.builder()
                    .name("No ID User")
                    .email("nouuid@example.com")
                    .build();

            when(passwordEncoder.encode(rawPassword)).thenReturn(encodedPassword);
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            User result = userService.registerUser(newUser, rawPassword);

            verify(userRepository).save(userCaptor.capture());
            User saved = userCaptor.getValue();
            assertThat(saved.getId()).isNotNull();
            assertThat(UUID.fromString(saved.getId())).isNotNull(); // valid UUID format
            assertThat(saved.getPasswordHash()).isEqualTo(encodedPassword);
        }

        @Test
        @DisplayName("should set default role to citizen if not provided")
        void shouldSetDefaultRole() {
            User newUser = User.builder()
                    .name("Default Role User")
                    .email("defaultrole@example.com")
                    .role(User.UserRole.citizen)
                    .build();

            when(passwordEncoder.encode(rawPassword)).thenReturn(encodedPassword);
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            User result = userService.registerUser(newUser, rawPassword);

            verify(userRepository).save(userCaptor.capture());
            assertThat(userCaptor.getValue().getRole()).isEqualTo(User.UserRole.citizen);
        }
    }

    @Nested
    @DisplayName("authenticateUser()")
    class AuthenticateUser {

        @Test
        @DisplayName("should return user when credentials are valid and account is active")
        void shouldReturnUserForValidCredentials() {
            when(userRepository.findByEmail(email)).thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches(rawPassword, encodedPassword)).thenReturn(true);

            Optional<User> result = userService.authenticateUser(email, rawPassword);

            assertThat(result).isPresent();
            assertThat(result.get().getId()).isEqualTo(userId);
            verify(userRepository).findByEmail(email);
            verify(passwordEncoder).matches(rawPassword, encodedPassword);
        }

        @Test
        @DisplayName("should return empty when password does not match")
        void shouldReturnEmptyForWrongPassword() {
            when(userRepository.findByEmail(email)).thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches(rawPassword, encodedPassword)).thenReturn(false);

            Optional<User> result = userService.authenticateUser(email, rawPassword);

            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("should return empty when email is not found")
        void shouldReturnEmptyForUnknownEmail() {
            when(userRepository.findByEmail(email)).thenReturn(Optional.empty());

            Optional<User> result = userService.authenticateUser(email, rawPassword);

            assertThat(result).isEmpty();
            verify(passwordEncoder, never()).matches(anyString(), anyString());
        }

        @Test
        @DisplayName("should return empty when user account is deleted")
        void shouldReturnEmptyForDeletedAccount() {
            testUser.setDeletedAt(LocalDateTime.now().minusDays(1));
            when(userRepository.findByEmail(email)).thenReturn(Optional.of(testUser));

            Optional<User> result = userService.authenticateUser(email, rawPassword);

            assertThat(result).isEmpty();
            verify(passwordEncoder, never()).matches(anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("getUserById()")
    class GetUserById {

        @Test
        @DisplayName("should return user when found")
        void shouldReturnUserWhenFound() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

            Optional<User> result = userService.getUserById(userId);

            assertThat(result).isPresent();
            assertThat(result.get().getEmail()).isEqualTo(email);
        }

        @Test
        @DisplayName("should return empty when not found")
        void shouldReturnEmptyWhenNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            Optional<User> result = userService.getUserById("unknown");

            assertThat(result).isEmpty();
        }
    }

    @Nested
    @DisplayName("updateUser()")
    class UpdateUser {

        @Test
        @DisplayName("should save updated user")
        void shouldSaveUpdatedUser() {
            testUser.setName("Updated Name");
            when(userRepository.save(testUser)).thenReturn(testUser);

            User result = userService.updateUser(testUser);

            assertThat(result.getName()).isEqualTo("Updated Name");
            verify(userRepository).save(testUser);
        }
    }

    @Nested
    @DisplayName("updateLastSeen()")
    class UpdateLastSeen {

        @Test
        @DisplayName("should update lastSeen timestamp when user exists")
        void shouldUpdateLastSeenForExistingUser() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            userService.updateLastSeen(userId);

            verify(userRepository).save(userCaptor.capture());
            assertThat(userCaptor.getValue().getLastSeen()).isNotNull();
        }

        @Test
        @DisplayName("should do nothing when user not found")
        void shouldDoNothingWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            userService.updateLastSeen("unknown");

            verify(userRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("deactivateUser()")
    class DeactivateUser {

        @Test
        @DisplayName("should set active to false when user exists")
        void shouldDeactivateExistingUser() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            userService.deactivateUser(userId);

            verify(userRepository).save(userCaptor.capture());
            assertThat(userCaptor.getValue().isActive()).isFalse();
        }

        @Test
        @DisplayName("should do nothing when user not found")
        void shouldDoNothingWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            userService.deactivateUser("unknown");

            verify(userRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("requestPasswordReset()")
    class RequestPasswordReset {

        @Test
        @DisplayName("should generate token and send email for valid user")
        void shouldSendResetEmailForValidUser() throws MessagingException {
            when(userRepository.findByEmail(email)).thenReturn(Optional.of(testUser));
            when(mailSender.createMimeMessage()).thenReturn(mimeMessage);
            doNothing().when(mailSender).send(any(MimeMessage.class));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            boolean result = userService.requestPasswordReset(email);

            assertThat(result).isTrue();
            verify(userRepository).save(userCaptor.capture());
            User saved = userCaptor.getValue();
            assertThat(saved.getPasswordResetToken()).isNotNull();
            assertThat(saved.getPasswordResetTokenExpiry()).isNotNull();
            assertThat(saved.getPasswordResetTokenExpiry()).isAfter(LocalDateTime.now());
            verify(mailSender).send(any(MimeMessage.class));
        }

        @Test
        @DisplayName("should return false when email not found")
        void shouldReturnFalseForUnknownEmail() {
            when(userRepository.findByEmail(email)).thenReturn(Optional.empty());

            boolean result = userService.requestPasswordReset(email);

            assertThat(result).isFalse();
            verify(mailSender, never()).send(any(MimeMessage.class));
        }

        @Test
        @DisplayName("should return false when user is deleted")
        void shouldReturnFalseForDeletedUser() {
            testUser.setDeletedAt(LocalDateTime.now().minusDays(1));
            when(userRepository.findByEmail(email)).thenReturn(Optional.of(testUser));

            boolean result = userService.requestPasswordReset(email);

            assertThat(result).isFalse();
            verify(mailSender, never()).send(any(MimeMessage.class));
        }

        @Test
        @DisplayName("should return false when mail sending fails")
        void shouldReturnFalseOnMailFailure() {
            when(userRepository.findByEmail(email)).thenReturn(Optional.of(testUser));
            when(mailSender.createMimeMessage()).thenReturn(mimeMessage);
            doThrow(new RuntimeException("SMTP error")).when(mailSender).send(any(MimeMessage.class));

            boolean result = userService.requestPasswordReset(email);

            assertThat(result).isFalse();
        }
    }

    @Nested
    @DisplayName("resetPassword()")
    class ResetPassword {

        @Test
        @DisplayName("should reset password with valid token")
        void shouldResetPasswordWithValidToken() {
            String token = UUID.randomUUID().toString();
            testUser.setPasswordResetToken(token);
            testUser.setPasswordResetTokenExpiry(LocalDateTime.now().plusHours(1));

            when(userRepository.findByPasswordResetToken(token)).thenReturn(Optional.of(testUser));
            when(passwordEncoder.encode("newPass123")).thenReturn("newEncodedHash");
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            boolean result = userService.resetPassword(token, "newPass123");

            assertThat(result).isTrue();
            verify(userRepository).save(userCaptor.capture());
            User saved = userCaptor.getValue();
            assertThat(saved.getPasswordHash()).isEqualTo("newEncodedHash");
            assertThat(saved.getPasswordResetToken()).isNull();
            assertThat(saved.getPasswordResetTokenExpiry()).isNull();
        }

        @Test
        @DisplayName("should return false when token is expired")
        void shouldReturnFalseForExpiredToken() {
            String token = UUID.randomUUID().toString();
            testUser.setPasswordResetToken(token);
            testUser.setPasswordResetTokenExpiry(LocalDateTime.now().minusHours(1));

            when(userRepository.findByPasswordResetToken(token)).thenReturn(Optional.of(testUser));

            boolean result = userService.resetPassword(token, "newPass123");

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }

        @Test
        @DisplayName("should return false when token is invalid")
        void shouldReturnFalseForInvalidToken() {
            when(userRepository.findByPasswordResetToken("invalid-token")).thenReturn(Optional.empty());

            boolean result = userService.resetPassword("invalid-token", "newPass123");

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }

        @Test
        @DisplayName("should return false when user is deleted")
        void shouldReturnFalseForDeletedUser() {
            String token = UUID.randomUUID().toString();
            testUser.setPasswordResetToken(token);
            testUser.setPasswordResetTokenExpiry(LocalDateTime.now().plusHours(1));
            testUser.setDeletedAt(LocalDateTime.now().minusDays(1));

            when(userRepository.findByPasswordResetToken(token)).thenReturn(Optional.of(testUser));

            boolean result = userService.resetPassword(token, "newPass123");

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("requestAccountDeletion()")
    class RequestAccountDeletion {

        @Test
        @DisplayName("should set deletionRequestedAt for valid user")
        void shouldSetDeletionRequestedAt() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            boolean result = userService.requestAccountDeletion(userId);

            assertThat(result).isTrue();
            verify(userRepository).save(userCaptor.capture());
            assertThat(userCaptor.getValue().getDeletionRequestedAt()).isNotNull();
        }

        @Test
        @DisplayName("should return false when user not found")
        void shouldReturnFalseWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            boolean result = userService.requestAccountDeletion("unknown");

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }

        @Test
        @DisplayName("should return false when user already deleted")
        void shouldReturnFalseWhenAlreadyDeleted() {
            testUser.setDeletedAt(LocalDateTime.now().minusDays(1));
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

            boolean result = userService.requestAccountDeletion(userId);

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("cancelAccountDeletion()")
    class CancelAccountDeletion {

        @Test
        @DisplayName("should clear deletionRequestedAt")
        void shouldClearDeletionRequestedAt() {
            testUser.setDeletionRequestedAt(LocalDateTime.now().minusDays(1));
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            boolean result = userService.cancelAccountDeletion(userId);

            assertThat(result).isTrue();
            verify(userRepository).save(userCaptor.capture());
            assertThat(userCaptor.getValue().getDeletionRequestedAt()).isNull();
        }

        @Test
        @DisplayName("should return false when no pending deletion")
        void shouldReturnFalseWhenNoPendingDeletion() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

            boolean result = userService.cancelAccountDeletion(userId);

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }

        @Test
        @DisplayName("should return false when user not found")
        void shouldReturnFalseWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            boolean result = userService.cancelAccountDeletion("unknown");

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("deleteUserAccount()")
    class DeleteUserAccount {

        @Test
        @DisplayName("should anonymize PII and mark as deleted")
        void shouldAnonymizeAndDelete() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            boolean result = userService.deleteUserAccount(userId);

            assertThat(result).isTrue();
            verify(userRepository).save(userCaptor.capture());
            User saved = userCaptor.getValue();
            assertThat(saved.getName()).contains("Deleted User");
            assertThat(saved.getEmail()).contains("@anon.dangeremergence.com");
            assertThat(saved.getPhone()).isNull();
            assertThat(saved.isActive()).isFalse();
            assertThat(saved.getDeletedAt()).isNotNull();
            assertThat(saved.getPasswordHash()).isNull();
            assertThat(saved.getPasswordResetToken()).isNull();
            assertThat(saved.getPasswordResetTokenExpiry()).isNull();
        }

        @Test
        @DisplayName("should return false when user not found")
        void shouldReturnFalseWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            boolean result = userService.deleteUserAccount("unknown");

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }

        @Test
        @DisplayName("should return false when already deleted")
        void shouldReturnFalseWhenAlreadyDeleted() {
            testUser.setDeletedAt(LocalDateTime.now().minusDays(1));
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

            boolean result = userService.deleteUserAccount(userId);

            assertThat(result).isFalse();
            verify(userRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("processPendingDeletions()")
    class ProcessPendingDeletions {

        @Test
        @DisplayName("should delete users whose grace period has expired")
        void shouldProcessExpiredDeletions() {
            User expiredUser = User.builder()
                    .id("expired-user")
                    .name("Expired User")
                    .email("expired@example.com")
                    .deletionRequestedAt(LocalDateTime.now().minusDays(31))
                    .build();

            when(userRepository.findPendingDeletions(any(LocalDateTime.class)))
                    .thenReturn(java.util.List.of(expiredUser));
            // processPendingDeletions() calls deleteUserAccount(user.getId()) which calls findById
            when(userRepository.findById("expired-user")).thenReturn(Optional.of(expiredUser));
            when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

            userService.processPendingDeletions();

            verify(userRepository).save(userCaptor.capture());
            User saved = userCaptor.getValue();
            assertThat(saved.getId()).isEqualTo("expired-user");
            assertThat(saved.getDeletedAt()).isNotNull();
            assertThat(saved.isActive()).isFalse();
        }

        @Test
        @DisplayName("should handle empty list gracefully")
        void shouldHandleEmptyList() {
            when(userRepository.findPendingDeletions(any(LocalDateTime.class)))
                    .thenReturn(java.util.List.of());

            userService.processPendingDeletions();

            verify(userRepository, never()).save(any());
        }
    }
}
