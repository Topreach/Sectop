package com.dangeremergence.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Redis caching layer for ML prediction results.
 *
 * Reduces load on the ML service by caching hotspot predictions,
 * area forecasts, and batch results with configurable TTLs.
 * Cache keys follow the pattern: "predict:{type}:{hash}"
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class PredictionCacheService {

    private static final String CACHE_PREFIX = "predict:";
    private static final String FORECAST_KEY_PREFIX = CACHE_PREFIX + "forecast:";
    private static final String HOTSPOT_KEY_PREFIX = CACHE_PREFIX + "hotspot:";
    private static final String BATCH_KEY_PREFIX = CACHE_PREFIX + "batch:";
    private static final String ALL_STATES_KEY = CACHE_PREFIX + "allstates";

    private final RedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    @Value("${predictive.cache.ttl.forecast:300}")
    private int forecastCacheTtlSeconds;

    @Value("${predictive.cache.ttl.hotspot:120}")
    private int hotspotCacheTtlSeconds;

    @Value("${predictive.cache.ttl.batch:600}")
    private int batchCacheTtlSeconds;

    /**
     * Cache a forecast response for an area.
     */
    public void cacheForecast(String cacheKey, Map<String, Object> forecast) {
        try {
            String redisKey = FORECAST_KEY_PREFIX + cacheKey;
            redisTemplate.opsForValue().set(redisKey, forecast, Duration.ofSeconds(forecastCacheTtlSeconds));
            log.debug("Cached forecast: {}", redisKey);
        } catch (Exception e) {
            log.warn("Failed to cache forecast: {}", e.getMessage());
        }
    }

    /**
     * Get a cached forecast response.
     */
    @SuppressWarnings("unchecked")
    public Optional<Map<String, Object>> getCachedForecast(String cacheKey) {
        try {
            String redisKey = FORECAST_KEY_PREFIX + cacheKey;
            Object cached = redisTemplate.opsForValue().get(redisKey);
            if (cached instanceof Map) {
                log.debug("Cache hit for forecast: {}", redisKey);
                return Optional.of((Map<String, Object>) cached);
            }
            return Optional.empty();
        } catch (Exception e) {
            log.warn("Failed to get cached forecast: {}", e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Cache hotspot detection results.
     */
    public void cacheHotspots(String cacheKey, List<Map<String, Object>> hotspots) {
        try {
            String redisKey = HOTSPOT_KEY_PREFIX + cacheKey;
            redisTemplate.opsForValue().set(redisKey, hotspots, Duration.ofSeconds(hotspotCacheTtlSeconds));
            log.debug("Cached hotspots: {}", redisKey);
        } catch (Exception e) {
            log.warn("Failed to cache hotspots: {}", e.getMessage());
        }
    }

    /**
     * Get cached hotspot detection results.
     */
    @SuppressWarnings("unchecked")
    public Optional<List<Map<String, Object>>> getCachedHotspots(String cacheKey) {
        try {
            String redisKey = HOTSPOT_KEY_PREFIX + cacheKey;
            Object cached = redisTemplate.opsForValue().get(redisKey);
            if (cached instanceof List) {
                log.debug("Cache hit for hotspots: {}", redisKey);
                return Optional.of((List<Map<String, Object>>) cached);
            }
            return Optional.empty();
        } catch (Exception e) {
            log.warn("Failed to get cached hotspots: {}", e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Cache batch forecast results.
     */
    public void cacheBatchForecast(String cacheKey, Map<String, Object> batchResult) {
        try {
            String redisKey = BATCH_KEY_PREFIX + cacheKey;
            redisTemplate.opsForValue().set(redisKey, batchResult, Duration.ofSeconds(batchCacheTtlSeconds));
            log.debug("Cached batch forecast: {}", redisKey);
        } catch (Exception e) {
            log.warn("Failed to cache batch forecast: {}", e.getMessage());
        }
    }

    /**
     * Get cached batch forecast results.
     */
    @SuppressWarnings("unchecked")
    public Optional<Map<String, Object>> getCachedBatchForecast(String cacheKey) {
        try {
            String redisKey = BATCH_KEY_PREFIX + cacheKey;
            Object cached = redisTemplate.opsForValue().get(redisKey);
            if (cached instanceof Map) {
                log.debug("Cache hit for batch forecast: {}", redisKey);
                return Optional.of((Map<String, Object>) cached);
            }
            return Optional.empty();
        } catch (Exception e) {
            log.warn("Failed to get cached batch forecast: {}", e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Cache the all-states forecast (longer TTL since it's expensive).
     */
    public void cacheAllStatesForecast(Map<String, Object> result) {
        try {
            redisTemplate.opsForValue().set(ALL_STATES_KEY, result, Duration.ofSeconds(batchCacheTtlSeconds));
            log.debug("Cached all-states forecast");
        } catch (Exception e) {
            log.warn("Failed to cache all-states forecast: {}", e.getMessage());
        }
    }

    /**
     * Get cached all-states forecast.
     */
    @SuppressWarnings("unchecked")
    public Optional<Map<String, Object>> getCachedAllStatesForecast() {
        try {
            Object cached = redisTemplate.opsForValue().get(ALL_STATES_KEY);
            if (cached instanceof Map) {
                log.debug("Cache hit for all-states forecast");
                return Optional.of((Map<String, Object>) cached);
            }
            return Optional.empty();
        } catch (Exception e) {
            log.warn("Failed to get cached all-states forecast: {}", e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Build a deterministic cache key from latitude, longitude, and radius.
     */
    public String buildAreaCacheKey(double latitude, double longitude, double radiusKm, int hours) {
        // Round to 2 decimal places for cache grouping
        double roundedLat = Math.round(latitude * 10.0) / 10.0;
        double roundedLng = Math.round(longitude * 10.0) / 10.0;
        int roundedRadius = (int) Math.round(radiusKm / 10.0) * 10;
        return String.format("%.1f_%.1f_%d_%dh", roundedLat, roundedLng, roundedRadius, hours);
    }

    /**
     * Evict all prediction caches (used after training).
     */
    public void evictAll() {
        try {
            redisTemplate.delete(redisTemplate.keys(CACHE_PREFIX + "*"));
            log.info("Evicted all prediction caches");
        } catch (Exception e) {
            log.warn("Failed to evict prediction caches: {}", e.getMessage());
        }
    }
}
