FROM --platform=$BUILDPLATFORM node:bookworm AS front-builder
WORKDIR /app
COPY frontend/ ./
RUN npm install && npm run build

FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS singbox-builder
LABEL maintainer="Alireza <alireza7@gmail.com>"
WORKDIR /app
ARG TARGETOS TARGETARCH
ARG SINGBOX_VER=v1.10.1
ARG SINGBOX_TAGS="with_quic,with_grpc,with_wireguard,with_ech,with_utls,with_reality_server,with_acme,with_v2ray_api,with_clash_api,with_gvisor"
ARG GOPROXY=""
ENV GOPROXY=${GOPROXY}
ENV CGO_ENABLED=0
ENV GOOS=$TARGETOS
ENV GOARCH=$TARGETARCH
RUN apt-get update -y && apt-get install -y build-essential gcc wget unzip
RUN set -ex \
    && git clone --depth 1 --branch $SINGBOX_VER https://github.com/SagerNet/sing-box.git \
    && cd sing-box \
    && go build -v -trimpath -tags \
        $SINGBOX_TAGS \
        -ldflags "-X \"github.com/sagernet/sing-box/constant.Version=$SINGBOX_VER\" -s -w -buildid=" \
        ./cmd/sing-box

FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS backend-builder
WORKDIR /app
ARG TARGETOS TARGETARCH
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
ENV CGO_ENABLED=1
ENV GOARCH=$TARGETARCH
ENV GOOS=$TARGETOS
RUN apt-get update -y && apt-get install -y build-essential gcc wget unzip
COPY backend/ ./
COPY --from=front-builder  /app/dist/ /app/web/html/
RUN go build -ldflags="-w -s" -o sui main.go

FROM debian:bookworm
LABEL org.opencontainers.image.authors="alireza7@gmail.com"
ENV TZ=Asia/Tehran
WORKDIR /usr/local/s-ui
RUN apt-get update -y && apt-get install -y \
	ca-certificates \
	tzdata \
	bash \
	iproute2 \
	iputils-ping \
	systemctl \
	procps \
	socat \
	tar \
	wget \
	curl \
	certbot
RUN mkdir /usr/local/s-ui/bin
COPY --from=singbox-builder /app/sing-box/sing-box /usr/local/s-ui/bin/
COPY --from=backend-builder  /app/sui /usr/local/s-ui/
COPY core/runSingbox.sh /usr/local/s-ui/bin/
COPY entrypoint.sh /usr/local/s-ui/
COPY sing-box.service /etc/systemd/system/
COPY s-ui.service /etc/systemd/system/
RUN echo \#\!/bin/bash >>/usr/local/s-ui/entrypoint.sh \
 && echo '(cd /usr/local/s-ui/bin/; ./runSingbox.sh)&' >>/usr/local/s-ui/entrypoint.sh \
 && echo /usr/local/s-ui/sui migrate>>/usr/local/s-ui/entrypoint.sh \
 && echo /usr/local/s-ui/sui >>/usr/local/s-ui/entrypoint.sh \
 && systemctl daemon-reload \
 && systemctl enable s-ui  --now \
 && systemctl enable sing-box --now 
RUN chmod +x /etc/systemd/system/s-ui.service \
	/etc/systemd/system/sing-box.service \
	/usr/local/s-ui/sui \
	/usr/local/s-ui/bin/sing-box \
	/usr/local/s-ui/bin/runSingbox.sh \
	/usr/local/s-ui/entrypoint.sh
VOLUME [ "/usr/local/s-ui/" ]
CMD [ "/usr/local/s-ui/entrypoint.sh" ]
