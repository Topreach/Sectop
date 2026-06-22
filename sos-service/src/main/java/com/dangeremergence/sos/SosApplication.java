package com.dangeremergence.sos;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Dedicated SOS Alert Microservice.
 * <p>
 * Runs on port 8081, isolated from the main application.
 * Handles ONLY SOS alert creation, processing, and real-time delivery.
 * If the main app crashes, SOS alerts still work.
 */
@SpringBootApplication
@EnableAsync
@EnableScheduling
public class SosApplication {

    public static void main(String[] args) {
        SpringApplication.run(SosApplication.class, args);
    }
}
