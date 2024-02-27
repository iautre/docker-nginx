# Docker

## 启动nginx

将nginx.conf 放到conf目录下

``` sehll
docker run -itd \
    --name=nginx \
    -p 80:80 \
    -p 443:443 \
    -p 443:443/udp \
    --network=docker_net \
    --network-alias=nginx \
    --restart=always \
    -v "$(pwd)/www":/var/www \
    -v "$(pwd)/logs":/var/logs \
    -v "$(pwd)/conf":/etc/nginx \
    iautre/nginx:quic
```

## 单系统架构

``` shell
docker build -t iautre/nginx .
```

## 多系统构架

``` shell
docker buildx build -t iautre/nginx --platform=linux/amd64,linux/arm64 . --push
```

``` shell
docker buildx build -t iautre/nginx --platform=linux/amd64 . --push
```


docker build -t iautre/nginx --platform=linux/amd64 . --push