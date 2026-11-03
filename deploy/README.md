# Деплой backend Xstore на VPS

Сервер поднимается одной командой Docker Compose: бэкенд, PostgreSQL и Caddy. Caddy сам выпускает и продлевает сертификат Let's Encrypt.

## Что нужно

- VPS на Ubuntu 22.04 или 24.04: от 1 ГБ RAM, диск — с запасом под IPA (от 20 ГБ).
- Домен или поддомен (например, `api.example.com`) с **A-записью на IP сервера**. Обновление DNS занимает от нескольких минут до суток; пока запись не видна, сертификат не выпустится.
- Открытые порты 22, 80 и 443.

## 1. Подготовить сервер

```bash
ssh root@<IP сервера>
curl -fsSL https://get.docker.com | sh
ufw allow 22 && ufw allow 80 && ufw allow 443 && ufw --force enable
```

## 2. Получить код и заполнить настройки

```bash
git clone https://github.com/Vladpryanik11/xstorexAPP.git /opt/istore
cd /opt/istore/deploy
cp .env.example .env
for k in POSTGRES_PASSWORD ADMIN_TOKEN GRANT_SECRET; do sed -i "s|^$k=.*|$k=$(openssl rand -hex 32)|" .env; done
nano .env   # вписать DOMAIN и ACME_EMAIL
```

`ADMIN_TOKEN` — ключ к админ-API. Храните его как пароль: в git `.env` не попадает.

## 3. Запустить

Проверьте, что домен уже указывает на сервер: `dig +short api.example.com` должен вернуть IP сервера. Затем:

```bash
docker compose up -d --build
docker compose ps                # все три сервиса — running / healthy
curl https://api.example.com/healthz
```

Ответ `{"ok":true}` означает, что HTTPS и бэкенд работают. Если сертификат не выпустился, смотрите `docker compose logs caddy`: почти всегда причина в DNS или в закрытом порту 80.

## 4. Наполнить каталог

Все команды ниже выполняются на сервере, из папки `deploy`.

```bash
set -a; . ./.env; set +a
A="https://$DOMAIN/admin/v1"; H="Authorization: Bearer $ADMIN_TOKEN"

# коды активации для пользователей
curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d '{"count":5,"plan_id":"month"}' $A/activation-codes

# категория
curl -s -X PUT -H "$H" -H 'Content-Type: application/json' \
  -d '{"kind":"apps","name":{"en":"Productivity","ru":"Продуктивность"},"sf_symbol":"checkmark.circle"}' \
  $A/categories/productivity

# приложение (иконка — любой https-URL)
curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d '{
  "id":"app_myapp","name":"My App","developer":"My Company","category_id":"productivity",
  "icon_url":"https://example.com/icon.png","tint_light":"#0041DC","tint_dark":"#6AA2E3","bg_color":"#EAF1FF",
  "description":{"en":"…","ru":"…"},"min_os":"15.0","published":true}' $A/apps

# текущий backend принимает IPA без серверной подписи; полноценный signer — обязательная задача Xstore
curl -s -X POST -H "$H" -F ipa=@MyApp.ipa -F version=1.0.0 -F build=1 -F notes='Первая версия' $A/apps/app_myapp/builds

# витрина вкладки «Приложения»
curl -s -X PUT -H "$H" -H 'Content-Type: application/json' \
  -d '{"rooms":[{"id":"apps_new","style":"shelf_one","title":"Новое","app_ids":["app_myapp"]}]}' \
  $A/storefront/apps
```

Полный список админ-маршрутов — в [docs/API.md](../docs/API.md).

## Кто сможет установить приложения

iOS ставит IPA вне App Store только на устройства, которые разрешены в профиле подписи этого IPA:

- **Ad Hoc / Development** — устройства, чьи UDID зарегистрированы в вашем аккаунте Apple Developer (до 100 iPhone в год на аккаунт). В профиль этого IPA нужно включить UDID устройства и переподписать IPA после добавления нового устройства.
- **Enterprise** — любые устройства, но только сотрудники вашей организации.

Это относится к существующему нативному клиенту iStore и к каждому приложению в каталоге.

## Обновление

```bash
cd /opt/istore && git pull && cd deploy && docker compose up -d --build
```

Миграции базы применяются автоматически при старте.

## Резервные копии

```bash
docker compose exec -T db pg_dump -U istore istore | gzip > /root/istore-db-$(date +%F).sql.gz
docker run --rm -v istore_storage:/data -v /root:/backup alpine tar czf /backup/istore-storage-$(date +%F).tgz -C /data .
```

Обе команды стоит поставить в cron и копировать архивы за пределы сервера.

## После запуска

В `ios/project.yml` поменяйте `ISTORE_API_BASE_URL` для Release на `https://<ваш домен>`.
