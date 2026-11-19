ARG ALPINE_VERSION=3.24.3
ARG NGINX_VERSION=1.31.9
ARG OPENSSL_VERSION=4.0.3
# ngx_brotli has no release tag after v1.0.0rc (2019), so pin the commit.
ARG NGX_BROTLI_COMMIT=53e0fb55f250f48fe80c0ddbf6c0f7103cdbaae1
ARG NGINX_SHA256=a11c5eeee2e257f4478f0e649f84b0040787d277d2d3e5233952aa6b6dcb80ad
ARG OPENSSL_SHA256=325b5c806167c13b40b1ffeadfe0248197c00eccc4cf123ec1e28d2d2fd216d9
# sha256 of the GitHub archive tarball above. GitHub may re-pack archives, so if
# this check starts failing, re-download the same commit and update the value.
ARG NGX_BROTLI_SHA256=27a4352dae4ba4922f9f013f3f0d02359aceeef2701872efa42849c3ba05457a
ARG ALPINE_MIRROR=

FROM alpine:${ALPINE_VERSION} AS builder

ARG NGINX_VERSION
ARG OPENSSL_VERSION
ARG NGX_BROTLI_COMMIT
ARG NGINX_SHA256
ARG OPENSSL_SHA256
ARG NGX_BROTLI_SHA256
ARG ALPINE_MIRROR
ARG NGINX_SOURCE_URL=https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
ARG OPENSSL_SOURCE_URL=https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz
ARG NGX_BROTLI_SOURCE_URL=https://github.com/google/ngx_brotli/archive/${NGX_BROTLI_COMMIT}.tar.gz

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

RUN set -eux \
    && wget "${NGX_BROTLI_SOURCE_URL}" -O /src/ngx_brotli.tar.gz \
    && echo "${NGX_BROTLI_SHA256}  /src/ngx_brotli.tar.gz" | sha256sum -c - \
    && mkdir -p /src/ngx_brotli \
    && tar -zxf /src/ngx_brotli.tar.gz -C /src/ngx_brotli --strip-components=1 \
    && rm /src/ngx_brotli.tar.gz

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
        --add-module=/src/ngx_brotli/static \
    && grep -q ngx_http_brotli_static_module objs/ngx_modules.c \
    && ! grep -q ngx_http_brotli_filter_module objs/ngx_modules.c \
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
