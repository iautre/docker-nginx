# docker-nginx

## 镜像

Docker Hub:

```shell
docker pull iautre/nginx:1.30.0
docker pull iautre/nginx:latest
```

GitHub Container Registry:

```shell
docker pull ghcr.io/iautre/nginx:1.30.0
docker pull ghcr.io/iautre/nginx:latest
```

CNB:

```shell
docker pull docker.cnb.cool/autre/nginx:1.30.0
docker pull docker.cnb.cool/autre/nginx:latest
```

## Docker Compose 部署

将 `nginx.conf` 和站点配置放到本地 `conf` 目录，将网站文件放到 `www` 目录。

HTTP/3/QUIC 需要同时映射 TCP `443` 和 UDP `443`。

```yaml
services:
  nginx:
    image: iautre/nginx:1.30.0
    container_name: nginx
    restart: always
    volumes:
      - ./conf:/etc/nginx:ro
      - ./logs:/var/logs
      - ./www:/var/www:ro
    ports:
      - 80:80
      - 443:443
      - 443:443/udp
    networks:
      - docker_net

networks:
  docker_net:
    external: true
    name: docker_net
```

启动服务：

```shell
docker compose up -d
```

查看日志：

```shell
docker compose logs -f nginx
```

停止服务：

```shell
docker compose down
```

容器内主要目录：

- 配置目录：`/etc/nginx`
- 网站目录：`/var/www`
- 日志目录：`/var/logs`