package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.config.SecurityConfig;
import com.dangeremergence.repository.UserRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = PublicController.class)
@Import(SecurityConfig.class)
class PublicControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JwtUtil jwtUtil;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @Nested
    @DisplayName("GET /api/v1/public/health")
    class Health {

        @Test
        @DisplayName("should return health status")
        void shouldReturnHealthStatus() throws Exception {
            mockMvc.perform(get("/api/v1/public/health"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("connected"))
                    .andExpect(jsonPath("$.service").value("Danger Emergence API"))
                    .andExpect(jsonPath("$.version").value("1.0.0"))
                    .andExpect(jsonPath("$.timestamp").isString());
        }
    }
}
