cd "$(dirname "$0")"
docker compose run --rm certbot renew
docker exec nginx-main nginx -s reload
