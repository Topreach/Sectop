package com.dangeremergence.sos.config;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.security.Key;
import java.util.Base64;
import java.util.Date;
import java.util.List;

/**
 * JWT utility for the SOS microservice.
 * Shares the same secret key as the main backend so tokens are interoperable.
 */
@Component
public class JwtUtil {

    @Value("${jwt.secret:defaultSecretKeyThatMustBeChangedInProductionEnvironment}")
    private String secret;

    @Value("${jwt.expiration:86400000}")
    private long expirationMs;

    private Key key;

    @PostConstruct
    public void init() {
        byte[] keyBytes = Base64.getDecoder().decode(
            Base64.getEncoder().encodeToString(secret.getBytes())
        );
        this.key = Keys.hmacShaKeyFor(keyBytes);
    }

    public String extractUserId(String token) {
        return extractAllClaims(token).getSubject();
    }

    public String extractRole(String token) {
        return extractAllClaims(token).get("role", String.class);
    }

    @SuppressWarnings("unchecked")
    public List<String> extractAuthorities(String token) {
        return extractAllClaims(token).get("authorities", List.class);
    }

    public boolean isTokenValid(String token) {
        try {
            Claims claims = extractAllClaims(token);
            return !claims.getExpiration().before(new Date());
        } catch (Exception e) {
            return false;
        }
    }

    private Claims extractAllClaims(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(key)
                .build()
                .parseClaimsJws(token)
                .getBody();
    }
}
