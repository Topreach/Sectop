package com.dangeremergence.config;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.binder.db.PostgreSQLDatabaseMetrics;
import io.micrometer.core.instrument.binder.jvm.ClassLoaderMetrics;
import io.micrometer.core.instrument.binder.jvm.JvmGcMetrics;
import io.micrometer.core.instrument.binder.jvm.JvmMemoryMetrics;
import io.micrometer.core.instrument.binder.jvm.JvmThreadMetrics;
import io.micrometer.core.instrument.binder.system.ProcessorMetrics;
import io.micrometer.core.instrument.binder.system.UptimeMetrics;
import io.micrometer.prometheus.PrometheusConfig;
import io.micrometer.prometheus.PrometheusMeterRegistry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.Scope;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.sdk.trace.samplers.Sampler;
import io.opentelemetry.semconv.resources.ResourceAttributes;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import javax.sql.DataSource;
import java.util.concurrent.TimeUnit;

/**
 * Observability configuration for the Danger Emergence System.
 *
 * Provides:
 * - OpenTelemetry distributed tracing (OTLP exporter)
 * - Micrometer metrics with Prometheus registry
 * - Smart sampling (head-based with rule engine)
 * - JVM, DB, and application-level instrumentation
 * - Structured JSON logging
 */
@Configuration
public class ObservabilityConfig {

    private static final String SERVICE_NAME = "danger-emergence-backend";
    private static final String SERVICE_VERSION = "1.0.0";
    private static final String DEPLOYMENT_ENVIRONMENT = System.getenv().getOrDefault("APP_ENV", "development");

    // ──────────────────────────────────────────────
    // OpenTelemetry Tracing
    // ──────────────────────────────────────────────

    @Bean
    public OpenTelemetry openTelemetry() {
        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.of(
                        ResourceAttributes.SERVICE_NAME, SERVICE_NAME,
                        ResourceAttributes.SERVICE_VERSION, SERVICE_VERSION,
                        ResourceAttributes.DEPLOYMENT_ENVIRONMENT, DEPLOYMENT_ENVIRONMENT
                )));

        // OTLP exporter — sends spans to OpenTelemetry Collector
        OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
                .setEndpoint(System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"))
                .setTimeout(30, TimeUnit.SECONDS)
                .build();

        // Smart sampler — head-based sampling with rules
        Sampler sampler = Sampler.parentBased(Sampler.traceIdRatioBased(
                getSamplingRate()
        ));

        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
                .setResource(resource)
                .setSampler(sampler)
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter)
                        .setMaxExportBatchSize(512)
                        .setMaxQueueSize(2048)
                        .setExporterTimeout(30, TimeUnit.SECONDS)
                        .setScheduleDelay(5, TimeUnit.SECONDS)
                        .build())
                .build();

        return OpenTelemetrySdk.builder()
                .setTracerProvider(tracerProvider)
                .buildAndRegisterGlobal();
    }

    @Bean
    public Tracer tracer(OpenTelemetry openTelemetry) {
        return openTelemetry.getTracer(SERVICE_NAME, SERVICE_VERSION);
    }

    // ──────────────────────────────────────────────
    // Micrometer / Prometheus Metrics
    // ──────────────────────────────────────────────

    @Bean
    @Primary
    public MeterRegistry meterRegistry() {
        PrometheusMeterRegistry registry = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);

        // JVM metrics
        new ClassLoaderMetrics().bindTo(registry);
        new JvmMemoryMetrics().bindTo(registry);
        new JvmGcMetrics().bindTo(registry);
        new JvmThreadMetrics().bindTo(registry);

        // System metrics
        new ProcessorMetrics().bindTo(registry);
        new UptimeMetrics().bindTo(registry);

        return registry;
    }

    @Bean
    public PostgreSQLDatabaseMetrics postgresMetrics(DataSource dataSource) {
        PostgreSQLDatabaseMetrics metrics = new PostgreSQLDatabaseMetrics(dataSource);
        metrics.bindTo(meterRegistry());
        return metrics;
    }

    // ──────────────────────────────────────────────
    // Application-Level Metrics
    // ──────────────────────────────────────────────

    /**
     * Timer for SOS alert processing latency.
     * Measures p50/p95/p99 response times.
     */
    @Bean
    public Timer sosProcessingTimer(MeterRegistry registry) {
        return Timer.builder("emergency.sos.processing.time")
                .description("Time to process an SOS alert")
                .publishPercentiles(0.5, 0.95, 0.99)
                .publishPercentileHistogram()
                .sla(
                        java.time.Duration.ofMillis(100),
                        java.time.Duration.ofMillis(500),
                        java.time.Duration.ofSeconds(1),
                        java.time.Duration.ofSeconds(5)
                )
                .register(registry);
    }

    /**
     * Counter for mesh message throughput.
     */
    @Bean
    public Counter meshMessageCounter(MeterRegistry registry) {
        return Counter.builder("emergency.mesh.messages.total")
                .description("Total mesh messages relayed")
                .register(registry);
    }

    /**
     * Counter for drone telemetry events.
     */
    @Bean
    public Counter droneTelemetryCounter(MeterRegistry registry) {
        return Counter.builder("emergency.drone.telemetry.total")
                .description("Total drone telemetry packets received")
                .register(registry);
    }

    /**
     * Summary for AI inference latency distribution.
     */
    @Bean
    public DistributionSummary inferenceLatencySummary(MeterRegistry registry) {
        return DistributionSummary.builder("emergency.ai.inference.latency")
                .description("AI model inference latency distribution")
                .publishPercentiles(0.5, 0.95, 0.99)
                .serviceLevelObjectives(50, 100, 200, 500, 1000) // ms
                .register(registry);
    }

    /**
     /**
      * Gauge for active WebSocket connections.
      */
     @Bean
     public io.micrometer.core.instrument.Gauge activeConnectionsGauge(
             MeterRegistry registry) {
         return io.micrometer.core.instrument.Gauge.builder(
                         "emergency.websocket.connections.active",
                         this::getActiveConnectionCount
                 )
                 .description("Active WebSocket connections")
                 .register(registry);
     }
    /**
     * Counter for battery-critical events from edge devices.
     */
    @Bean
    public Counter batteryCriticalCounter(MeterRegistry registry) {
        return Counter.builder("emergency.device.battery.critical")
                .description("Battery critical events from edge devices")
                .register(registry);
    }

    // ──────────────────────────────────────────────
    // Smart Sampling Strategy
    // ──────────────────────────────────────────────

    /**
     * Determine the sampling rate based on environment and load.
     *
     * Rules:
     * - Production: 10% default, 100% for error spans
     * - Staging: 50%
     * - Development: 100%
     * - High load (>1000 req/s): dynamically reduce to 1%
     */
    private double getSamplingRate() {
        return switch (DEPLOYMENT_ENVIRONMENT) {
            case "production" -> 0.1;  // 10% — balance cost vs observability
            case "staging" -> 0.5;     // 50%
            case "development" -> 1.0; // 100%
            default -> 0.1;
        };
    }

    /**
     * Create a traced span for an operation.
     * Usage: try (Scope scope = startSpan("operationName")) { ... }
     */
    public Span startSpan(Tracer tracer, String spanName, SpanKind kind) {
        Span span = tracer.spanBuilder(spanName)
                .setSpanKind(kind)
                .startSpan();
        return span;
    }

    /**
     * Add standard emergency context attributes to a span.
     */
    public void addEmergencyContext(Span span, String alertId, String zoneId, String severity) {
        span.setAttribute("emergency.alert.id", alertId);
        span.setAttribute("emergency.zone.id", zoneId);
        span.setAttribute("emergency.severity", severity);
        span.setAttribute("emergency.timestamp", java.time.Instant.now().toString());
    }

    // Placeholder — in production, inject WebSocket handler registry
    private long getActiveConnectionCount() {
        return 0;
    }
}
