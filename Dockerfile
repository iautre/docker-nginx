ARG ALPINE_VERSION=3.24.1
ARG NGINX_VERSION=1.31.3
ARG OPENSSL_VERSION=3.5.7
ARG NGINX_SHA256=a7657c50811c2d92d9895395e8b873ef60398142c4db21eb647811c38f6dd525
ARG OPENSSL_SHA256=a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8
ARG ALPINE_MIRROR=

FROM alpine:${ALPINE_VERSION} AS builder

ARG NGINX_VERSION
ARG OPENSSL_VERSION
ARG NGINX_SHA256
ARG OPENSSL_SHA256
ARG ALPINE_MIRROR
ARG NGINX_SOURCE_URL=https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
ARG OPENSSL_SOURCE_URL=https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz

WORKDIR /src

RUN set -eux \
    && if [ -n "${ALPINE_MIRROR}" ]; then sed -i "s|https://dl-cdn.alpinelinux.org/alpine|${ALPINE_MIRROR}|g" /etc/apk/repositories; fi \
    && apk add --no-cache --virtual .build-deps \
                ca-certificates \
                build-base \
                perl \
                zlib-dev \
                zlib-static \
                pcre2-dev \
                pcre2-static \
                linux-headers

RUN set -eux \
    && wget "${OPENSSL_SOURCE_URL}" -O "/src/openssl-${OPENSSL_VERSION}.tar.gz" \
    && echo "${OPENSSL_SHA256}  /src/openssl-${OPENSSL_VERSION}.tar.gz" | sha256sum -c - \
    && tar -zxf "/src/openssl-${OPENSSL_VERSION}.tar.gz" -C /src \
    && mv "/src/openssl-${OPENSSL_VERSION}" /src/openssl \
    && rm "/src/openssl-${OPENSSL_VERSION}.tar.gz"

RUN set -eux \
    && wget "${NGINX_SOURCE_URL}" -O "/src/nginx-${NGINX_VERSION}.tar.gz" \
    && echo "${NGINX_SHA256}  /src/nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c - \
    && tar -zxf "/src/nginx-${NGINX_VERSION}.tar.gz" -C /src \
    && rm "/src/nginx-${NGINX_VERSION}.tar.gz"

WORKDIR /src/openssl
RUN set -eux \
    && ./Configure \
        --prefix=/src/openssl/build \
        --openssldir=/src/openssl/build/ssl \
        --libdir=lib \
        no-shared \
        no-apps \
        no-tests \
        -O2 \
        -fstack-protector-strong \
        -D_FORTIFY_SOURCE=2 \
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
        --with-cc-opt="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -I/src/openssl/build/include" \
        --with-ld-opt="-L/src/openssl/build/lib -static -Wl,-z,relro,-z,now -Wl,--as-needed" \
        --with-threads \
        --with-file-aio \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-http_realip_module \
        --with-pcre-jit \
        --with-http_gzip_static_module \
        --with-http_gunzip_module \
    && make -j"$(nproc)" \
    && make install \
    && strip -s /usr/local/nginx/sbin/nginx \
    && mkdir -p /var/run/nginx /var/logs

FROM alpine:${ALPINE_VERSION} AS production

ARG ALPINE_VERSION
ARG NGINX_VERSION
ARG ALPINE_MIRROR

LABEL maintainer="a little <little@autre.cn> https://coding.autre.cn" \
      org.opencontainers.image.title="docker-nginx" \
      org.opencontainers.image.description="NGINX with HTTP/3 and QUIC support" \
      org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.base.name="alpine:${ALPINE_VERSION}" \
      org.opencontainers.image.source="https://github.com/iautre/docker-nginx"

COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /etc/nginx /etc/nginx

RUN set -eux \
    && if [ -n "${ALPINE_MIRROR}" ]; then sed -i "s|https://dl-cdn.alpinelinux.org/alpine|${ALPINE_MIRROR}|g" /etc/apk/repositories; fi \
    && apk add --no-cache ca-certificates tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && apk del tzdata \
    && ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx \
    && addgroup -g 111 -S www \
    && adduser -S -D -H -u 111 -h /var/cache/nginx -s /sbin/nologin -G www -g www www \
    && mkdir -p /run/nginx /var/cache/nginx /var/logs \
    && chown www:www /var/cache/nginx \
    && ln -sf /dev/stdout /var/logs/access.log \
    && ln -sf /dev/stderr /var/logs/error.log

EXPOSE 80/tcp 443/tcp 443/udp
STOPSIGNAL SIGQUIT
CMD ["nginx", "-g", "daemon off;"]
