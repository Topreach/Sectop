package com.dangeremergence.controller;

import com.dangeremergence.service.RouteService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.util.Map;

/**
 * STOMP message controller for real-time safe route planning via WebSocket.
 *
 * Handles route planning requests sent via STOMP SEND frames from the frontend
 * WebSocket connection. This is faster than HTTP POST because it reuses the
 * existing WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * The route result is sent back to the requesting user via their personal queue:
 *   /user/queue/route/result
 *
 * Destination: /app/route/plan
 * Mapped from: SEND destination:/app/route/plan
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompRouteController {

    private final RouteService routeService;
    private final SimpMessagingTemplate messagingTemplate;

    /**
     * Handle a safe route planning request via STOMP SEND frame.
     * Computes the route and sends the result back to the user's personal queue.
     */
    @MessageMapping("/route/plan")
    public void handleRoutePlan(@Payload Map<String, Object> payload,
                                 SimpMessageHeaderAccessor headerAccessor) {
        try {
            String userId = (String) payload.get("userId");
            Number fromLatNum = (Number) payload.get("fromLat");
            Number fromLngNum = (Number) payload.get("fromLng");
            Number toLatNum = (Number) payload.get("toLat");
            Number toLngNum = (Number) payload.get("toLng");
            boolean avoidHighways = payload.get("avoidHighways") != null && (Boolean) payload.get("avoidHighways");
            boolean preferLitRoads = payload.get("preferLitRoads") != null && (Boolean) payload.get("preferLitRoads");

            if (fromLatNum == null || fromLngNum == null || toLatNum == null || toLngNum == null) {
                log.warn("STOMP route plan missing required coordinates");
                if (userId != null) {
                    messagingTemplate.convertAndSendToUser(userId, "/queue/route/result",
                            Map.of("error", "Missing required coordinates", "success", false));
                }
                return;
            }

            double fromLat = fromLatNum.doubleValue();
            double fromLng = fromLngNum.doubleValue();
            double toLat = toLatNum.doubleValue();
            double toLng = toLngNum.doubleValue();

            // Delegate to RouteService (computes safe route with danger scoring)
            Map<String, Object> route = routeService.planSafeRoute(
                    fromLat, fromLng, toLat, toLng, avoidHighways, preferLitRoads);

            // Send result back to the requesting user via their personal queue
            if (userId != null) {
                messagingTemplate.convertAndSendToUser(userId, "/queue/route/result",
                        Map.of("data", route, "success", true));
            }

            log.debug("STOMP route planned: from=({},{}), to=({},{})", fromLat, fromLng, toLat, toLng);
        } catch (Exception e) {
            log.error("STOMP route planning failed: {}", e.getMessage());
        }
    }
}
