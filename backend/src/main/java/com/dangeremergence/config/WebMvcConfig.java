package com.dangeremergence.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web MVC configuration to serve uploaded media files as static resources.
 * <p>
 * Maps the {@code /uploads/**} URL path to the local filesystem directory
 * so that community post media (images/videos) can be accessed by the frontend.
 */
@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        // Serve uploaded community media files
        registry.addResourceHandler("/uploads/**")
                .addResourceLocations("file:uploads/");
    }
}
