package com.dangeremergence.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * Global geocoding service using the Nominatim (OpenStreetMap) API.
 * Resolves GPS coordinates to country/region/city names worldwide.
 * Falls back to NigeriaLocationService for Nigeria-specific resolution
 * when the Nominatim API is unreachable.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class GeoLocationService {

    private static final String NOMINATIM_REVERSE_URL =
            "https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&addressdetails=1";

    private final NigeriaLocationService nigeriaLocationService;
    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Resolve GPS coordinates to a location string (country, region, city).
     *
     * @param latitude  GPS latitude
     * @param longitude GPS longitude
     * @return String array with [country, region, city, displayName].
     *         Falls back to NigeriaLocationService for Nigeria coordinates
     *         if Nominatim is unreachable.
     */
    public String[] resolve(double latitude, double longitude) {
        try {
            // Set a proper User-Agent as required by Nominatim usage policy
            String response = restTemplate.getForObject(
                    NOMINATIM_REVERSE_URL,
                    String.class,
                    latitude,
                    longitude
            );

            if (response == null || response.isEmpty()) {
                log.warn("Nominatim returned empty response for {}, {}", latitude, longitude);
                return fallback(latitude, longitude);
            }

            JsonNode root = objectMapper.readTree(response);
            JsonNode address = root.get("address");

            if (address == null) {
                log.warn("Nominatim response missing 'address' for {}, {}", latitude, longitude);
                return fallback(latitude, longitude);
            }

            String country = safeGet(address, "country", "Unknown");
            String region = safeGet(address, "state",
                    safeGet(address, "region",
                            safeGet(address, "province", "")));
            String city = safeGet(address, "city",
                    safeGet(address, "town",
                            safeGet(address, "village",
                                    safeGet(address, "municipality", ""))));
            String displayName = safeGet(root, "display_name",
                    String.format("%.4f, %.4f", latitude, longitude));

            log.info("Nominatim resolved {}, {} -> country={}, region={}, city={}",
                    latitude, longitude, country, region, city);

            return new String[]{country, region, city, displayName};

        } catch (Exception e) {
            log.warn("Nominatim API call failed for {}, {}: {}. Using fallback.",
                    latitude, longitude, e.getMessage());
            return fallback(latitude, longitude);
        }
    }

    /**
     * Fallback: use NigeriaLocationService for Nigeria coordinates,
     * return generic "Unknown" for other locations.
     */
    private String[] fallback(double latitude, double longitude) {
        if (nigeriaLocationService.isInNigeria(latitude, longitude)) {
            String[] ngInfo = nigeriaLocationService.resolve(latitude, longitude);
            return new String[]{"Nigeria", ngInfo[0], ngInfo[1],
                    String.format("%s, %s, Nigeria", ngInfo[1], ngInfo[0])};
        }
        return new String[]{"Unknown", "Unknown", "Unknown",
                String.format("%.4f, %.4f", latitude, longitude)};
    }

    /**
     * Check if coordinates are within Nigeria (delegates to NigeriaLocationService).
     */
    public boolean isInNigeria(double latitude, double longitude) {
        return nigeriaLocationService.isInNigeria(latitude, longitude);
    }

    /**
     * Get country name for coordinates.
     */
    public String getCountry(double latitude, double longitude) {
        return resolve(latitude, longitude)[0];
    }

    /**
     * Get region/state name for coordinates.
     */
    public String getRegion(double latitude, double longitude) {
        return resolve(latitude, longitude)[1];
    }

    /**
     * Get city name for coordinates.
     */
    public String getCity(double latitude, double longitude) {
        return resolve(latitude, longitude)[2];
    }

    /**
     * Safely extract a text field from a JsonNode, with fallback.
     */
    private String safeGet(JsonNode node, String field, String fallback) {
        JsonNode value = node.get(field);
        if (value != null && !value.isNull()) {
            String text = value.asText();
            if (!text.isEmpty()) {
                return text;
            }
        }
        return fallback;
    }

    /**
     * Overloaded safeGet with chained fallback.
     */
    private String safeGet(JsonNode node, String field, String fallbackField, String fallback) {
        String result = safeGet(node, field, null);
        if (result != null) return result;
        return safeGet(node, fallbackField, fallback);
    }
}
