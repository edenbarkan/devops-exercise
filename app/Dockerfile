# syntax=docker/dockerfile:1
# Multi-stage, multi-arch build. The builder runs natively on the build host
# ($BUILDPLATFORM) and cross-compiles for $TARGETARCH, so arm64+amd64 builds
# need no QEMU emulation. Base images are pinned by digest.

FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine@sha256:f2c872bcee949b7be9c490efd02b48a8a2fbf947cdf533f1c58525ec9d8170fd AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
ARG TARGETOS TARGETARCH
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/hello .

# Distroless static: no shell, no package manager, CA certs + tzdata only.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087
COPY --from=build /out/hello /hello
# Numeric UID so Kubernetes can verify runAsNonRoot.
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/hello"]
