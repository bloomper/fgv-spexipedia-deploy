# fgv-spexipedia-deploy

Docker Compose for Spexipedia, FGV's encyclopedia of the Chalmers spex: the API (`fgv-spexipedia-server`), the web
(`fgv-spexipedia-web`), MySQL and `spexipedia-media`, an nginx that serves the images. It runs next to
`fgv-infra-deploy` (Keycloak, Umami, the shared network `fgv-<env>`) and the other applications' deploy repositories.

```
Browser ──https──▶ Cloudflare (CDN) ──tunnel──▶ spexipedia-web:3000
                                             └─▶ spexipedia-media:80   (/media/*)

spexipedia-web ──▶ spexipedia-api ──▶ spexipedia-mysql
spexipedia-api ──▶ keycloak-server, spexregister-api, spexgram-api, spexify-api, spexflix-api, archive-api  (fgv network)
spexregister-api, revival-api, spexify-api, spexflix-api, archive-api, spexgram-api ──▶ spexipedia-api      (fgv network)
```

Spexipedia is public: visitors read published pages without logging in, so there is no Cloudflare Access in front of
it. The API is reached only from the web and the shared network; public GraphQL goes through the web.

## 1. Before you start

- `fgv-infra-deploy` is running for the same environment, with `SPEXIPEDIA_NAME` and `SPEXIPEDIA_WEB_HOST` in its
  `.env`, and its `bin/init-secrets.sh` and `bin/configure-keycloak.sh` have run (they make the clients
  `fgv-spexipedia` and `fgv-spexipedia-service` and their secrets).
- Check this repository out next to `fgv-infra-deploy` and `spexregister-deploy`.

## 2. Configure

```shell
cp staging.env.example .env        # or production.env.example
bin/init-secrets.sh                # copies the client secrets, generates the rest
nano secrets/cloudflared.env       # staging only: TUNNEL_TOKEN=<token>
mkdir -p data/api/log_data data/media data/uploads
sudo chown -R 1000:1000 data
```

`bin/init-secrets.sh` copies `fgv-spexipedia` and `fgv-spexipedia-service` from
`../fgv-infra-deploy/secrets/clients/`, and with `API_IMPORT_SAMPLE_DATA=true` also `fgv-admin` (the sample data gives
the sample users their roles) and `SAMPLE_USER_PASSWORD` from `../spexregister-deploy`. Set `INFRA_DEPLOY` or
`SPEXREGISTER_DEPLOY` for other layouts. You can run it again safely.

| Variable | Meaning |
|----------|---------|
| `WEB_HOST` | Spexipedia's hostname; the images are under `/media/` on it |
| `KEYCLOAK_HOST`, `KEYCLOAK_REALM` | The FGV realm |
| `API_IMAGE`, `WEB_IMAGE` | The images to run |
| `*_GRAPHQL_URL` | The other applications' APIs on the shared network, which Spexipedia asks for people (Spexregister), photos (Spexgram) and links (Spexify, Spexflix, Spexarkivet). Each may be missing; its parts of the pages are then left out |
| `*_WEB_URL` | The other applications' addresses, for the application switcher and links |
| `SPEXGRAM_MEDIA_ORIGIN` | `https://` and Spexgram's `MEDIA_HOST`: the pages' Content Security Policy allows its photos and videos; without it, Spexgram's videos do not play |
| `API_IMPORT_SAMPLE_DATA` | `true` replaces everything with sample data at every start (refused in `production`) |
| `UMAMI_WEBSITE_ID` | The website's id in Umami (see `fgv-infra-deploy`, *Umami*); empty sends nothing |

## 3. Start

```shell
docker compose up -d
docker compose logs -f spexipedia-api
```

**Sample data comes first.** Spexipedia is the source of spex, categories and tasks. Start it before
`spexregister-deploy`: Spexregister's sample import waits for Spexipedia's change feed. Spexipedia then gives
Spexregister's sample users their roles as they appear (`admin@fgv.nu`, `editor@fgv.nu`, `user@fgv.nu`) and creates
`author@fgv.nu`.

**Change recipients.** After a change to base data Spexipedia tells the applications that copy it, as
`fgv-spexipedia-service`. The sample data adds them all; in production add them under *Administration → Mottagare av
ändringar* with their service account and notify address, e.g. `spexregister-service` and
`http://spexregister-api:8080/api/sync/notify`. Each also pulls the feed itself every five minutes.

## Staging

`compose.tunnel.yaml` adds `cloudflared`. In the tunnel's public hostnames, route `WEB_HOST` with path `/media/*` to
`http://spexipedia-media:80` first, and `WEB_HOST` to `http://spexipedia-web:3000`. Cache `/media/*` at Cloudflare;
the addresses never change for a file.

## Production

Production's reverse proxy does the same: `/media/` on `WEB_HOST` to `spexipedia-media:80`, the rest to
`spexipedia-web:3000`. Public pages may be cached briefly; pages with a session cookie never.

## Backups

- `bin/backup-db.sh` dumps the database into `backups/` (kept `BACKUP_KEEP_DAYS`, 14).
- `bin/backup-media.sh` copies the images' originals off the host with restic (`RESTIC_REPOSITORY`,
  `RESTIC_PASSWORD_FILE`). The variants are made again from the originals by the maintenance job *Bildstorlekar*.

## Moving `spexipedia.fgv.nu` from the MediaWiki

At M5, when the MediaWiki's content has been migrated (`fgv-spexipedia-migration`), point `spexipedia.fgv.nu` at this
deployment. Old addresses (`/<Title>`, `/index.php?title=<Title>`) are answered with permanent redirects from the
redirect table, kept by admins under *Administration → Omdirigeringar*.
