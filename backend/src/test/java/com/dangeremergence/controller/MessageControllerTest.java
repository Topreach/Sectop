package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.model.Message;
import com.dangeremergence.service.MessageService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = MessageController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class MessageControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private MessageService messageService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private JwtUtil jwtUtil;

    private Message testMessage;
    private static final String MESSAGE_ID = "msg-123";
    private static final String SENDER_ID = "sender-123";
    private static final String RECEIVER_ID = "receiver-123";

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());

        testMessage = new Message();
        testMessage.setId(MESSAGE_ID);
        testMessage.setSender(null);
        testMessage.setReceiver(null);
        testMessage.setContent("Hello, this is a test message");
        testMessage.setMessageType(Message.MessageType.text);
        testMessage.setPriority(0);
        testMessage.setStatus(Message.MessageStatus.sent);
        testMessage.setSyncState(Message.SyncState.pending);
        testMessage.setCreatedAt(LocalDateTime.now());
    }

    @Nested
    class SendMessage {

        @Test
        void shouldSendMessageSuccessfully() throws Exception {
            when(messageService.sendMessage(
                    eq(SENDER_ID), eq(RECEIVER_ID), eq("Hello"),
                    eq(Message.MessageType.text), eq(0), isNull(), isNull()
            )).thenReturn(testMessage);

            Map<String, Object> request = Map.of(
                    "sender_id", SENDER_ID,
                    "receiver_id", RECEIVER_ID,
                    "content", "Hello",
                    "message_type", "text"
            );

            mockMvc.perform(post("/api/v1/messages")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request))
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(MESSAGE_ID))
                    .andExpect(jsonPath("$.content").value("Hello, this is a test message"));
        }

        @Test
        void shouldSendMessageWithLocation() throws Exception {
            when(messageService.sendMessage(
                    eq(SENDER_ID), eq(RECEIVER_ID), eq("I'm here"),
                    eq(Message.MessageType.text), eq(1), eq(6.5), eq(3.3)
            )).thenReturn(testMessage);

            Map<String, Object> request = Map.of(
                    "sender_id", SENDER_ID,
                    "receiver_id", RECEIVER_ID,
                    "content", "I'm here",
                    "priority", 1,
                    "latitude", 6.5,
                    "longitude", 3.3
            );

            mockMvc.perform(post("/api/v1/messages")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request))
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk());
        }

        @Test
        void shouldSendAlertMessage() throws Exception {
            when(messageService.sendMessage(
                    eq(SENDER_ID), eq(RECEIVER_ID), eq("Emergency!"),
                    eq(Message.MessageType.alert), eq(5), isNull(), isNull()
            )).thenReturn(testMessage);

            Map<String, Object> request = Map.of(
                    "sender_id", SENDER_ID,
                    "receiver_id", RECEIVER_ID,
                    "content", "Emergency!",
                    "message_type", "alert",
                    "priority", 5
            );

            mockMvc.perform(post("/api/v1/messages")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request))
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class GetMessages {

        @Test
        void shouldGetMessagesForUser() throws Exception {
            when(messageService.getMessagesForUser(RECEIVER_ID))
                    .thenReturn(List.of(testMessage));

            mockMvc.perform(get("/api/v1/messages/user/{userId}", RECEIVER_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messages[0].id").value(MESSAGE_ID));
        }

        @Test
        void shouldGetMessagesSince() throws Exception {
            when(messageService.getMessagesSince(eq(RECEIVER_ID), any(LocalDateTime.class)))
                    .thenReturn(List.of(testMessage));

            mockMvc.perform(get("/api/v1/messages/sync")
                            .param("userId", RECEIVER_ID)
                            .param("since", "2024-01-01T00:00:00")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messages[0].id").value(MESSAGE_ID));
        }

        @Test
        void shouldGetPendingSyncMessages() throws Exception {
            when(messageService.getPendingSyncMessages())
                    .thenReturn(List.of(testMessage));

            mockMvc.perform(get("/api/v1/messages/pending-sync")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messages[0].id").value(MESSAGE_ID));
        }

        @Test
        void shouldGetUnreadCount() throws Exception {
            when(messageService.getUnreadCount(RECEIVER_ID)).thenReturn(3L);

            mockMvc.perform(get("/api/v1/messages/unread/{userId}", RECEIVER_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.count").value(3));
        }
    }

    @Nested
    class MarkMessage {

        @Test
        void shouldMarkAsDelivered() throws Exception {
            when(messageService.markAsDelivered(MESSAGE_ID)).thenReturn(testMessage);

            mockMvc.perform(put("/api/v1/messages/{messageId}/deliver", MESSAGE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(MESSAGE_ID));
        }

        @Test
        void shouldMarkAsRead() throws Exception {
            when(messageService.markAsRead(MESSAGE_ID)).thenReturn(testMessage);

            mockMvc.perform(put("/api/v1/messages/{messageId}/read", MESSAGE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(MESSAGE_ID));
        }

        @Test
        void shouldMarkAsSynced() throws Exception {
            mockMvc.perform(put("/api/v1/messages/{messageId}/sync", MESSAGE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk());
        }
    }
}
