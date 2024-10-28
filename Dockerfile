FROM alpine as builder

LABEL maintainer="a little <little@autre.cn> https://coding.autre.cn"

ARG NGINX_VERSION=1.27.2
ARG OPENSSL_QUIC_VERSION=3.3.0

WORKDIR /src

RUN set -x \
    # && sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
    && apk update \
    && apk upgrade \
    && apk add --no-cache --virtual .build-deps \
                ca-certificates \
                build-base \
                patch \
                cmake \
                git \
                mercurial \
                perl \
                libatomic_ops-dev \
                libatomic_ops-static \
                zlib-dev \
                zlib-static \
                pcre-dev \
                linux-headers
RUN set -x \
    # && git clone --recursive https://github.com/quictls/openssl /src/openssl 
    && wget https://github.com/quictls/openssl/archive/refs/tags/openssl-${OPENSSL_QUIC_VERSION}-quic1.tar.gz -O /src/openssl-${OPENSSL_QUIC_VERSION}-quic1.tar.gz \
    # && wget https://d7.serctl.com/downloads8/2023-05-24-10-43-45-openssl-openssl-3.0.8-quic1.tar.gz -O /src/openssl-${OPENSSL_QUIC_VERSION}-quic1.tar.gz \
    && tar -zxvf /src/openssl-${OPENSSL_QUIC_VERSION}-quic1.tar.gz -C /src \
    && mv /src/openssl-openssl-${OPENSSL_QUIC_VERSION}-quic1 /src/openssl
    # && ls -la /src/openssl
RUN set -x \
    && wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    && tar -zxvf nginx-${NGINX_VERSION}.tar.gz 

WORKDIR /src/openssl
RUN set -x \
    && /src/openssl/Configure \
    && make

WORKDIR /src/nginx-${NGINX_VERSION}
RUN set -x \
    && ./configure \
        --prefix=/usr/local/nginx \
        --user=www \
        --group=www \
        --pid-path=/var/run/nginx/nginx.pid \
        --lock-path=/var/run/nginx/nginx.lock \
        --error-log-path=/var/logs/error.log \
        --http-log-path=/var/logs/access.log \
        --conf-path=/etc/nginx/nginx.conf \
        --with-openssl="/src/openssl" \
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
    && make \
    && make install \
    && strip -s /usr/local/nginx/sbin/nginx
    #&& apk del .build-deps

FROM alpine as production 

COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /var/run/nginx /var/run/nginx
COPY --from=builder /var/logs /var/logs
COPY --from=builder /etc/nginx /etc/nginx

RUN set -x \
    # && sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
    && apk update \
    && apk upgrade \
    && apk add --no-cache tzdata pcre-dev \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && apk del tzdata \
    && rm -rf /tmp/* /var/cache/apk/* \
    && ln -s /usr/local/nginx/sbin/nginx /usr/bin/ \
    && ln -sf /dev/stdout /var/logs/access.log \
    && ln -sf /dev/stderr /var/logs/error.log \
    && addgroup -g 111 -S www \
    && adduser -S -D -u 111 -s /sbin/nologin -G www -g www www
    #&& chown -R www:www /etc/nginx && chown -R www:www /var/logs \
    
##挂载目录
VOLUME ["/etc/nginx","/var/www","/var/logs"]
##conf目录： /etc/nginx
WORKDIR /run/nginx
#开放端口
EXPOSE 80 443
STOPSIGNAL SIGTERM
CMD ["nginx","-g","daemon off;"]
