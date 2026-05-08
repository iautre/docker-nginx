ARG ALPINE_VERSION=3.23.3

FROM alpine:${ALPINE_VERSION} AS builder

ARG ALPINE_VERSION
ARG NGINX_VERSION=1.30.0
ARG OPENSSL_QUIC_VERSION=3.5.6

LABEL maintainer="a little <little@autre.cn> https://coding.autre.cn" \
      org.opencontainers.image.title="docker-nginx" \
      org.opencontainers.image.description="NGINX with HTTP/3 and QUIC support" \
      org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.base.name="alpine:${ALPINE_VERSION}" \
      org.opencontainers.image.source="https://github.com/autre/docker-nginx"

WORKDIR /src

RUN set -eux \
    && apk add --no-cache --virtual .build-deps \
                ca-certificates \
                build-base \
                perl \
                libatomic_ops-dev \
                libatomic_ops-static \
                zlib-dev \
                zlib-static \
                pcre2-dev \
                pcre2-static \
                linux-headers

RUN set -eux \
    && wget "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_QUIC_VERSION}/openssl-${OPENSSL_QUIC_VERSION}.tar.gz" -O "/src/openssl-${OPENSSL_QUIC_VERSION}.tar.gz" \
    && tar -zxf "/src/openssl-${OPENSSL_QUIC_VERSION}.tar.gz" -C /src \
    && mv "/src/openssl-${OPENSSL_QUIC_VERSION}" /src/openssl

RUN set -eux \
    && wget "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O "/src/nginx-${NGINX_VERSION}.tar.gz" \
    && tar -zxf "/src/nginx-${NGINX_VERSION}.tar.gz" -C /src

WORKDIR /src/openssl
RUN set -eux \
    && ./Configure \
        --prefix=/src/openssl/build \
        --openssldir=/src/openssl/build/ssl \
        --libdir=lib \
        no-shared \
        no-tests \
    && make -j"$(nproc)" \
    && make install_sw

WORKDIR /src/nginx-${NGINX_VERSION}
RUN set -eux \
    && ./configure \
        --prefix=/usr/local/nginx \
        --user=www \
        --group=www \
        --pid-path=/var/run/nginx/nginx.pid \
        --lock-path=/var/run/nginx/nginx.lock \
        --error-log-path=/var/logs/error.log \
        --http-log-path=/var/logs/access.log \
        --conf-path=/etc/nginx/nginx.conf \
        --with-cc-opt="-I/src/openssl/build/include" \
        --with-ld-opt="-L/src/openssl/build/lib -static" \
        --with-threads \
        --with-file-aio \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-http_gunzip_module \
    && make -j"$(nproc)" \
    && make install \
    && strip -s /usr/local/nginx/sbin/nginx \
    && mkdir -p /var/run/nginx /var/logs

FROM alpine:${ALPINE_VERSION} AS production

ARG ALPINE_VERSION
ARG NGINX_VERSION=1.30.0
ARG OPENSSL_QUIC_VERSION=3.5.6

LABEL maintainer="a little <little@autre.cn> https://coding.autre.cn" \
      org.opencontainers.image.title="docker-nginx" \
      org.opencontainers.image.description="NGINX with HTTP/3 and QUIC support" \
      org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.base.name="alpine:${ALPINE_VERSION}" \
      org.opencontainers.image.source="https://github.com/autre/docker-nginx"

COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /var/run/nginx /var/run/nginx
COPY --from=builder /var/logs /var/logs
COPY --from=builder /etc/nginx /etc/nginx

RUN set -eux \
    && apk add --no-cache tzdata pcre2 zlib libatomic_ops \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && apk del tzdata \
    && rm -rf /tmp/* /var/cache/apk/* \
    && ln -s /usr/local/nginx/sbin/nginx /usr/bin/ \
    && ln -sf /dev/stdout /var/logs/access.log \
    && ln -sf /dev/stderr /var/logs/error.log \
    && addgroup -g 111 -S www \
    && adduser -S -D -u 111 -s /sbin/nologin -G www -g www www

##挂载目录
VOLUME ["/etc/nginx","/var/www","/var/logs"]
##conf目录： /etc/nginx
WORKDIR /run/nginx
#开放端口
EXPOSE 80 443
STOPSIGNAL SIGTERM
CMD ["nginx","-g","daemon off;"]
