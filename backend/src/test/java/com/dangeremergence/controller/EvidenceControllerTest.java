package com.dangeremergence.controller;

import com.dangeremergence.model.Evidence;
import com.dangeremergence.service.EvidenceService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
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

import java.util.List;

import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = EvidenceController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class EvidenceControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private EvidenceService evidenceService;

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
    }

    private Evidence createSampleEvidence() {
        Evidence evidence = new Evidence();
        evidence.setId("ev_001");
        evidence.setParentId("parent_001");
        evidence.setParentType("incident");
        evidence.setEvidenceType("photo");
        evidence.setFileName("photo.jpg");
        evidence.setMimeType("image/jpeg");
        evidence.setSizeBytes(1024L);
        return evidence;
    }

    @Nested
    @DisplayName("POST /api/v1/evidence")
    class UploadEvidence {

        @Test
        @DisplayName("should upload evidence successfully")
        void shouldUploadEvidence() throws Exception {
            Evidence evidence = createSampleEvidence();
            when(evidenceService.storeEvidence(anyString(), anyString(), anyString(), anyString(),
                    anyString(), anyLong(), anyString(), anyDouble(), anyDouble())).thenReturn(evidence);

            String request = """
                    {
                        "parentId": "parent_001",
                        "parentType": "incident",
                        "evidenceType": "photo",
                        "fileName": "photo.jpg",
                        "mimeType": "image/jpeg",
                        "sizeBytes": 1024,
                        "fileContent": "base64encodedcontent"
                    }
                    """;

            mockMvc.perform(post("/api/v1/evidence")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.id").value("ev_001"))
                    .andExpect(jsonPath("$.parentId").value("parent_001"));
        }

        @Test
        @DisplayName("should return 400 when required fields are missing")
        void shouldReturn400WhenFieldsMissing() throws Exception {
            String request = """
                    {
                        "fileName": "photo.jpg"
                    }
                    """;

            mockMvc.perform(post("/api/v1/evidence")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/evidence/{id}")
    class GetEvidence {

        @Test
        @DisplayName("should return evidence by ID")
        void shouldReturnEvidenceById() throws Exception {
            Evidence evidence = createSampleEvidence();
            when(evidenceService.getEvidence("ev_001")).thenReturn(evidence);

            mockMvc.perform(get("/api/v1/evidence/ev_001")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value("ev_001"));
        }

        @Test
        @DisplayName("should return 404 when evidence not found")
        void shouldReturn404WhenNotFound() throws Exception {
            when(evidenceService.getEvidence("nonexistent")).thenThrow(new RuntimeException("Not found"));

            mockMvc.perform(get("/api/v1/evidence/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/evidence/parent/{parentId}")
    class GetEvidenceForParent {

        @Test
        @DisplayName("should return evidence list for parent")
        void shouldReturnEvidenceForParent() throws Exception {
            when(evidenceService.getEvidenceForParent("parent_001")).thenReturn(List.of(createSampleEvidence()));

            mockMvc.perform(get("/api/v1/evidence/parent/parent_001")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value("ev_001"));
        }
    }

    @Nested
    @DisplayName("DELETE /api/v1/evidence/{id}")
    class DeleteEvidence {

        @Test
        @DisplayName("should delete evidence by ID")
        void shouldDeleteEvidence() throws Exception {
            mockMvc.perform(delete("/api/v1/evidence/ev_001")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNoContent());
        }

        @Test
        @DisplayName("should return 404 when evidence not found")
        void shouldReturn404WhenNotFound() throws Exception {
            doThrow(new RuntimeException("Not found")).when(evidenceService).deleteEvidence("nonexistent");

            mockMvc.perform(delete("/api/v1/evidence/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("DELETE /api/v1/evidence/parent/{parentId}")
    class DeleteEvidenceForParent {

        @Test
        @DisplayName("should delete all evidence for parent")
        void shouldDeleteEvidenceForParent() throws Exception {
            mockMvc.perform(delete("/api/v1/evidence/parent/parent_001")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNoContent());
        }
    }
}
