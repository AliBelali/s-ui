FROM --platform=$BUILDPLATFORM node:bookworm as front-builder
WORKDIR /app
COPY frontend/ ./
RUN npm install && npm run build

FROM golang:1.22-bookworm AS backend-builder
WORKDIR /app
ARG TARGETARCH
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
ENV CGO_ENABLED=1
ENV GOARCH=$TARGETARCH
RUN apt-get update -y && apt-get install -y build-essential gcc wget unzip
COPY backend/ ./
COPY --from=front-builder  /app/dist/ /app/web/html/
RUN go build -ldflags="-w -s" -o sui main.go
RUN git clone -b v1.8.14 https://github.com/SagerNet/sing-box
RUN cd sing-box \
 && go build -v -gcflags=all="-l -B -C" -mod=mod -trimpath \
	-ldflags "-s -w -buildid= -extldflags '-static'" -a \
	-tags='netgo osusergo static_build with_quic with_grpc with_wireguard with_ech with_utls with_reality_server with_acme with_v2ray_api with_clash_api with_gvisor' \
	-o sing-box ./cmd/sing-box 

FROM --platform=$TARGETPLATFORM debian:bookworm
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
COPY --from=backend-builder  /app/sui /usr/local/s-ui/
COPY --from=backend-builder  /app/sing-box/sing-box /usr/local/s-ui/bin/
COPY core/runSingbox.sh /usr/local/s-ui/bin/
COPY sing-box.service /etc/systemd/system/
COPY s-ui.service /etc/systemd/system/
RUN echo \#\!/bin/bash >>/usr/local/s-ui/entrypoint.sh \
 && echo '(cd /usr/local/s-ui/bin/;exec ./runSingbox.sh)&' >>/usr/local/s-ui/entrypoint.sh \
 && echo exec /usr/local/s-ui/sui >>/usr/local/s-ui/entrypoint.sh \
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
