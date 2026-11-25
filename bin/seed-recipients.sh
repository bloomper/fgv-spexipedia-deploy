#!/usr/bin/env bash
# Registers the applications that copy Spexipedia's base data as change recipients (Administration -> Mottagare av
# ändringar), as the sample data does, but without replacing anything else. Run it once after the first start, in
# staging and production alike. It can be run again safely: a recipient that already exists (by service account) is
# left as it is, so changes made in the administration stay.
#
# It writes to the database directly because the administration needs a signed-in administrator, which a script
# does not have. The applications read the feed themselves every five minutes, so they need no restart.
set -euo pipefail

cd "$(dirname "$0")/.."

# name | service account | address Spexipedia notifies after each change
recipients=(
  "Spexregister|fgv-spexregister-service|http://spexregister-api:8080/api/sync/notify"
  "Spexify|fgv-spexify-service|http://spexify-api:8080/api/sync/notify"
  "Spexflix|fgv-spexflix-service|http://spexflix-api:8080/api/sync/notify"
  "Spexgram|fgv-spexgram-service|http://spexgram-api:8080/api/sync/notify"
  "Spexarkivet|fgv-archive-service|http://archive-api:8080/api/sync/notify"
)

sql=""
for recipient in "${recipients[@]}"; do
  IFS='|' read -r name client url <<< "$recipient"
  sql+="INSERT IGNORE INTO sync_consumer (uuid, name, client_id, notify_url, enabled) VALUES (UUID(), '$name', '$client', '$url', 1);"$'\n'
done

# Names and addresses above are fixed text without quotes, so they need no escaping
printf '%s' "$sql" | docker compose exec -T spexipedia-mysql sh -c \
  'MYSQL_PWD=$(cat /run/secrets/MYSQL_ROOT_PASSWORD) exec mysql -uroot --default-character-set=utf8mb4 "$MYSQL_DATABASE"'

docker compose exec -T spexipedia-mysql sh -c \
  'MYSQL_PWD=$(cat /run/secrets/MYSQL_ROOT_PASSWORD) exec mysql -uroot --default-character-set=utf8mb4 "$MYSQL_DATABASE" -e "SELECT name, client_id, notify_url, enabled FROM sync_consumer ORDER BY name"'
