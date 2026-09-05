# Hardcoded rather than BUILD_FROM/build.yaml: the Supervisor validates build_from against
# ^([a-zA-Z\-\.:\d{}]+/)*?([\-\w{}]+)/([\-\w{}]+)(:[\.\-\w{}]+)?$ — which needs a two-segment
# repo path. "mcr.microsoft.com/playwright" is single-segment, so the value is rejected, one
# warning is logged, and ghcr.io/home-assistant/base:latest (Alpine) is substituted silently.
# The build then died far downstream on `apt-get: not found`. The tag is multi-arch
# (linux/amd64 + linux/arm64), so one FROM covers both arches this add-on declares.
FROM mcr.microsoft.com/playwright:v1.63.0-noble@sha256:eff16c30e6f3f4af0a03fa4b706120d5e9b0891c344a27d64559aff5900a4a27

# Labels
LABEL maintainer="chodeus"
LABEL io.hass.version="0.1.0"
LABEL io.hass.type="addon"
LABEL io.hass.arch="amd64,aarch64"
LABEL org.opencontainers.image.title="Playwright Browser for Home Assistant"
LABEL org.opencontainers.image.description="Headless Chromium with CDP endpoint for browser automation"
LABEL org.opencontainers.image.source="https://github.com/chodeus/robsonfelix-hass-addons"
LABEL org.opencontainers.image.licenses="MIT"

# jq is already available in the Playwright image (Ubuntu-based)
# Just ensure it's installed
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq curl nginx && \
    rm -rf /var/lib/apt/lists/*

# Create data directory
RUN mkdir -p /data

# Copy run script
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Expose CDP port
EXPOSE 9222

# Health check - verify CDP endpoint responds
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:9222/json/version || exit 1

CMD ["/run.sh"]
