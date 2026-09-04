# nginx-main

以 Docker Compose 運行的 nginx 反向代理主機，作為多個服務共用的對外入口，並整合 Let's Encrypt（certbot）自動簽發與續期憑證。

## 架構

| 元件 | 說明 |
| --- | --- |
| `nginx` (`nginx:alpine`) | 對外開放 80 / 443，容器名稱 `nginx-main` |
| `certbot` (`certbot/certbot`) | 以 one-off 方式執行，負責簽發與 renew 憑證 |
| `nginx-net` | 外部 Docker network，其他服務加入這個網路後即可被 nginx 代理 |

### 目錄與掛載

| 主機路徑 | 容器內路徑 | 用途 |
| --- | --- | --- |
| `./conf.d` | `/etc/nginx/conf.d` | nginx 站台設定（**不進版控**） |
| `./certbot/conf` | `/etc/letsencrypt` | 憑證與 certbot 設定（**不進版控**） |
| `./certbot/www` | `/var/www/certbot` | ACME `http-01` challenge 的 webroot |

> `.gitignore` 已排除 `conf.d/*`、`certbot/*`、`renew.log`，實際設定與憑證只存在於部署機器上。

## 前置需求

- Docker / Docker Compose
- [Task](https://taskfile.dev)（選用，未安裝可直接用 `docker compose` 指令）

## 啟動

```bash
task up        # 若 nginx-net 不存在會先建立，再 docker compose up -d
task down      # docker compose down
task restart   # down 後再 up
```

不使用 Task 的等價操作：

```bash
docker network create nginx-net   # 只需執行一次
docker compose up -d
```

## 新增一個站台

1. 在 `conf.d/` 底下新增 `<domain>.conf`。
2. 反向代理目標請用「容器名稱」，該容器需一併加入 `nginx-net` 這個外部網路。
3. 重新載入設定：

   ```bash
   docker exec nginx-main nginx -t       # 先驗證語法
   docker exec nginx-main nginx -s reload
   ```

設定範例：

```nginx
server {
    listen 80;
    server_name example.com;

    # 保留給 certbot 做 http-01 challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location / {
        proxy_pass http://your-app-container:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 憑證

### 首次簽發

先確保該網域的 80 port 設定已生效（含 `/.well-known/acme-challenge/` 區塊），再執行：

```bash
docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d example.com \
  --email you@example.com --agree-tos --no-eff-email
```

簽發成功後，補上 443 的 server 區塊並 `nginx -s reload`。

### 續期

`renew.sh` 會 renew 所有憑證並重新載入 nginx：

```bash
./renew.sh
```

建議掛到 cron 定期執行（Let's Encrypt 憑證效期 90 天，到期前 30 天內才會實際更新）：

```cron
0 3 * * 1 /path/to/nginx-main/renew.sh >> /path/to/nginx-main/renew.log 2>&1
```

## 疑難排解

| 症狀 | 檢查方向 |
| --- | --- |
| `network nginx-net not found` | 先 `docker network create nginx-net`，或改用 `task up` |
| 代理回 502 | 目標容器是否已加入 `nginx-net`、`proxy_pass` 的容器名與 port 是否正確 |
| nginx 起不來 | `docker compose logs nginx`、`docker exec nginx-main nginx -t` |
| certbot challenge 失敗 | 網域 A record 是否指向本機、80 port 是否對外開放、`/.well-known/acme-challenge/` 是否指到 `/var/www/certbot` |
