package com.dangeremergence.service;

import com.dangeremergence.model.SubscriptionTier;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/**
 * Service for integrating with Paystack payment gateway.
 * Handles transaction initialization, verification, and webhook signature validation.
 */
@Service
public class PaystackService {

    private static final Logger LOGGER = LoggerFactory.getLogger(PaystackService.class);

    private final String secretKey;
    private final String apiUrl;
    private final String callbackUrl;
    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    @Autowired
    public PaystackService(
            @Value("${paystack.secret-key:}") String secretKey,
            @Value("${paystack.api-url:https://api.paystack.co}") String apiUrl,
            @Value("${paystack.callback-url:}") String callbackUrl) {
        this.secretKey = secretKey;
        this.apiUrl = apiUrl;
        this.callbackUrl = callbackUrl;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(15))
                .build();
        this.objectMapper = new ObjectMapper();
    }

    /**
     * Check if Paystack is configured (secret key is set).
     */
    public boolean isConfigured() {
        return secretKey != null && !secretKey.isBlank();
    }

    /**
     * Initialize a Paystack transaction for a subscription payment.
     *
     * @param email    The customer's email address
     * @param amount   The amount in kobo (e.g., 150000 for ₦1,500)
     * @param metadata Additional data to attach to the transaction
     * @return Map with "authorization_url" and "reference" on success, or "error" on failure
     */
    public Map<String, Object> initializeTransaction(String email, int amount, Map<String, Object> metadata) {
        if (!isConfigured()) {
            LOGGER.warn("Paystack is not configured. Set PAYSTACK_SECRET_KEY environment variable.");
            return Map.of("error", "Payment gateway not configured");
        }

        try {
            Map<String, Object> body = new HashMap<>();
            body.put("email", email);
            body.put("amount", amount);
            body.put("currency", "NGN");
            if (callbackUrl != null && !callbackUrl.isBlank()) {
                body.put("callback_url", callbackUrl);
            }
            if (metadata != null) {
                body.put("metadata", metadata);
            }

            String jsonBody = objectMapper.writeValueAsString(body);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(apiUrl + "/transaction/initialize"))
                    .header("Authorization", "Bearer " + secretKey)
                    .header("Content-Type", "application/json")
                    .header("Cache-Control", "no-cache")
                    .timeout(Duration.ofSeconds(30))
                    .POST(HttpRequest.BodyPublishers.ofString(jsonBody))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            JsonNode json = objectMapper.readTree(response.body());

            if (json.has("status") && json.get("status").asBoolean()) {
                JsonNode data = json.get("data");
                Map<String, Object> result = new HashMap<>();
                result.put("authorization_url", data.get("authorization_url").asText());
                result.put("reference", data.get("reference").asText());
                result.put("access_code", data.has("access_code") ? data.get("access_code").asText() : "");
                return result;
            } else {
                String message = json.has("message") ? json.get("message").asText() : "Unknown error";
                LOGGER.error("Paystack initialization failed: {}", message);
                return Map.of("error", message);
            }
        } catch (Exception e) {
            LOGGER.error("Failed to initialize Paystack transaction", e);
            return Map.of("error", "Failed to connect to payment gateway: " + e.getMessage());
        }
    }

    /**
     * Verify a Paystack transaction by reference.
     *
     * @param reference The transaction reference returned from initializeTransaction
     * @return Map with transaction details on success, or "error" on failure
     */
    public Map<String, Object> verifyTransaction(String reference) {
        if (!isConfigured()) {
            return Map.of("error", "Payment gateway not configured");
        }

        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(apiUrl + "/transaction/verify/" + reference))
                    .header("Authorization", "Bearer " + secretKey)
                    .header("Cache-Control", "no-cache")
                    .timeout(Duration.ofSeconds(30))
                    .GET()
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            JsonNode json = objectMapper.readTree(response.body());

            if (json.has("status") && json.get("status").asBoolean()) {
                JsonNode data = json.get("data");
                Map<String, Object> result = new HashMap<>();
                result.put("status", data.get("status").asText());
                result.put("amount", data.get("amount").asInt());
                result.put("currency", data.get("currency").asText());
                result.put("paid_at", data.has("paid_at") && !data.get("paid_at").isNull()
                        ? data.get("paid_at").asText() : "");
                result.put("reference", data.get("reference").asText());

                // Extract metadata if present
                if (data.has("metadata") && !data.get("metadata").isNull()) {
                    JsonNode metadata = data.get("metadata");
                    if (metadata.has("tier")) {
                        result.put("tier", metadata.get("tier").asText());
                    }
                    if (metadata.has("userId")) {
                        result.put("userId", metadata.get("userId").asText());
                    }
                    if (metadata.has("durationMonths")) {
                        result.put("durationMonths", metadata.get("durationMonths").asInt());
                    }
                }

                return result;
            } else {
                String message = json.has("message") ? json.get("message").asText() : "Verification failed";
                LOGGER.error("Paystack verification failed for {}: {}", reference, message);
                return Map.of("error", message);
            }
        } catch (Exception e) {
            LOGGER.error("Failed to verify Paystack transaction {}", reference, e);
            return Map.of("error", "Failed to verify payment: " + e.getMessage());
        }
    }

    /**
     * Validate a Paystack webhook signature.
     * Paystack sends an "x-paystack-signature" header which is the HMAC-SHA512
     * of the raw request body, signed with your secret key.
     *
     * @param signature The signature from the "x-paystack-signature" header
     * @param body      The raw request body as a string
     * @return true if the signature is valid
     */
    public boolean validateWebhookSignature(String signature, String body) {
        if (secretKey == null || secretKey.isBlank()) {
            return false;
        }
        try {
            Mac mac = Mac.getInstance("HmacSHA512");
            SecretKeySpec keySpec = new SecretKeySpec(secretKey.getBytes(StandardCharsets.UTF_8), "HmacSHA512");
            mac.init(keySpec);
            byte[] hash = mac.doFinal(body.getBytes(StandardCharsets.UTF_8));
            String computedSignature = Base64.getEncoder().encodeToString(hash);
            return MessageDigest.isEqual(signature.getBytes(StandardCharsets.UTF_8),
                    computedSignature.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            LOGGER.error("Failed to validate webhook signature", e);
            return false;
        }
    }

    /**
     * Get the amount in kobo for a given subscription tier and duration.
     * Paystack amounts are in the smallest currency unit (kobo for NGN).
     */
    public static int getAmountInKobo(SubscriptionTier tier, int durationMonths) {
        int monthlyPrice = switch (tier) {
            case premium -> 1500;
            case family -> 2500;
            default -> 0;
        };

        if (durationMonths >= 12) {
            // Annual pricing: Premium = ₦12,000/year, Family = ₦25,000/year (no annual discount for family)
            int annualPrice = switch (tier) {
                case premium -> 12000;
                case family -> 2500 * 12; // No annual discount for family
                default -> 0;
            };
            return annualPrice * 100; // Convert to kobo
        }

        return monthlyPrice * durationMonths * 100; // Convert to kobo
    }

    /**
     * Get the Paystack product ID for a given tier and duration.
     * These would be created in your Paystack dashboard under Products.
     */
    public static String getProductId(SubscriptionTier tier, int durationMonths) {
        if (durationMonths >= 12) {
            return switch (tier) {
                case premium -> "PREMIUM_ANNUAL";
                case family -> "FAMILY_ANNUAL";
                default -> "FREE";
            };
        }
        return switch (tier) {
            case premium -> "PREMIUM_MONTHLY";
            case family -> "FAMILY_MONTHLY";
            default -> "FREE";
        };
    }
}
