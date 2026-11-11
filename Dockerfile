# syntax=docker/dockerfile:1

ARG GO_VERSION=1
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS builder

ARG TAILSCALE_VERSION
ARG TAILSCALE_REVISION
ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
RUN test -n "$TAILSCALE_VERSION" && test -n "$TAILSCALE_REVISION" && \
    git init && \
    git remote add origin https://github.com/tailscale/tailscale.git && \
    git fetch --depth=1 origin "refs/tags/v${TAILSCALE_VERSION}:refs/tags/v${TAILSCALE_VERSION}" && \
    git checkout --detach "v${TAILSCALE_VERSION}" && \
    test "$(git rev-parse HEAD)" = "$TAILSCALE_REVISION"

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" \
    ./build_dist.sh --strip -o /out/derper ./cmd/derper

FROM debian:bookworm-slim

RUN mkdir -p /var/lib/derper/certs
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ARG TAILSCALE_VERSION
ARG TAILSCALE_REVISION
ARG BUILD_REVISION
ARG SOURCE_URL=https://github.com/Goalonez/z-tailscale-derp

LABEL org.opencontainers.image.title="z-tailscale-derp" \
      org.opencontainers.image.description="Tailscale DERP relay server built from upstream source" \
      org.opencontainers.image.source="$SOURCE_URL" \
      org.opencontainers.image.version="$TAILSCALE_VERSION" \
      org.opencontainers.image.revision="$BUILD_REVISION" \
      io.tailscale.revision="$TAILSCALE_REVISION"

COPY --from=builder /out/derper /usr/local/bin/derper
COPY --from=builder /src/LICENSE /usr/share/doc/derper/LICENSE
COPY LICENSE /usr/share/doc/z-tailscale-derp/LICENSE

EXPOSE 80/tcp 443/tcp 3478/udp
WORKDIR /var/lib/derper
ENTRYPOINT ["/usr/local/bin/derper"]
CMD ["--help"]
