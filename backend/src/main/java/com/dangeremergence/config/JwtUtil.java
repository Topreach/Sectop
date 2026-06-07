package com.dangeremergence.config;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.util.Date;

@Component
public class JwtUtil {

    private final Key signingKey;
    private final long expirationMs;

    public JwtUtil(@Value("${JWT_SECRET:change-this-secret}") String secret,
                   @Value("${JWT_EXPIRATION_MS:86400000}") long expirationMs) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expirationMs = expirationMs;
    }

    public String generateToken(String userId, String email, String role) {
        final long now = System.currentTimeMillis();
        return Jwts.builder()
                .setSubject(userId)
                .claim("email", email)
                .claim("role", role)
                .setIssuedAt(new Date(now))
                .setExpiration(new Date(now + expirationMs))
                .signWith(signingKey, SignatureAlgorithm.HS256)
                .compact();
    }

    public String generateTokenWithExpiry(String userId, String email, String role, long customExpirationMs, boolean emergency) {
        final long now = System.currentTimeMillis();
        var builder = Jwts.builder()
                .setSubject(userId)
                .claim("email", email)
                .claim("role", role)
                .setIssuedAt(new Date(now))
                .setExpiration(new Date(now + customExpirationMs))
                .signWith(signingKey, SignatureAlgorithm.HS256);
        if (emergency) builder.claim("emergency", true);
        return builder.compact();
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parserBuilder().setSigningKey(signingKey).build().parseClaimsJws(token);
            return true;
        } catch (JwtException | IllegalArgumentException ex) {
            return false;
        }
    }

    public String getUserIdFromToken(String token) {
        Claims claims = Jwts.parserBuilder().setSigningKey(signingKey).build().parseClaimsJws(token).getBody();
        return claims.getSubject();
    }

    public String getRoleFromToken(String token) {
        Claims claims = Jwts.parserBuilder().setSigningKey(signingKey).build().parseClaimsJws(token).getBody();
        Object role = claims.get("role");
        return role != null ? role.toString() : null;
    }
}
