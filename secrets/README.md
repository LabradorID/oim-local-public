# Secrets

The OIM App Server and API Server containers read configuration from files inside
`/run/secrets/`. The `docker-compose.oim.yml` file mounts the two folders below
into those containers:

- `secrets/appserver/` → mounted into `oim-appserver:/run/secrets`
- `secrets/apiserver/` → mounted into `oim-apiserver:/run/secrets`

This repository ships **only `.example` template files**. Before you start the
ready environment, copy each `*.example` to its real name (without the suffix)
and fill in real values.

## App Server (`secrets/appserver/`)

| File                     | Purpose                                                              |
|--------------------------|----------------------------------------------------------------------|
| `CONNSTRING`             | ADO.NET connection string the App Server uses to reach OneIM.       |
| `DBSYSTEM`               | Database backend (set to `MSSQL`).                                  |
| `SessionCertificate.pfx` | PKCS#12 certificate used to sign session tokens. **Required.**      |

## API Server (`secrets/apiserver/`)

| File                      | Purpose                                                                                  |
|---------------------------|------------------------------------------------------------------------------------------|
| `CONNSTRING`              | Direct DB connection (used during initial register).                                     |
| `DBSYSTEM`                | Database backend (`MSSQL`).                                                              |
| `BASEURL`                 | Public URL the API Server is reachable at, e.g. `http://localhost:8182/`.                |
| `APPSERVERCONNSTRING`     | URL of the App Server, prefixed with `Url=`. Must match the host the portal session uses (typically the host IP, NOT `appserver`). |
| `TRUSTEDSOURCEKEY`        | Clear-text key that registers this API Server as a trusted source. The matching hash is written into `QBMWebApplication.TrustedSourceKey` on first start. |
| `UPDATEUSER`              | OneIM user/password used for schema updates.                                             |
| `SessionCertificate.pfx`  | PKCS#12 certificate. **Required.**                                                       |

### Generating a self-signed session certificate

```bash
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
    -days 3650 -nodes -subj "/CN=oim-apiserver"
openssl pkcs12 -export -out SessionCertificate.pfx \
    -inkey key.pem -in cert.pem -passout pass:
```

Copy `SessionCertificate.pfx` into both `secrets/appserver/` and
`secrets/apiserver/`.

### `APPSERVERCONNSTRING` gotcha

The value MUST start with `Url=`, e.g.:

```
Url=http://172.31.163.58:8080/
```

The URL has to match the AppServer URL that the portal session actually uses
(usually the host IP, not the internal Docker hostname `appserver`). Without the
`Url=` prefix the API Server cannot register the AppServer connection, and
portal features that delegate to the AppServer (e.g. Lucene-backed search) fail
with:

```
[810432] Die Verbindung "http://...:8080/" wurde in der Konfiguration nicht gefunden.
```

### Editing secrets after the first start

The OIM container entrypoint (`/usr/bin/run.sh`) only generates `web.config`
from the secret files **on the first container start**. It then writes a marker
file `/tmp/Initialized.marker` and on every subsequent start it skips
`updatewebcfg`.

> Editing a secret file and running `docker compose restart` does NOT take
> effect — the live `web.config` still contains values baked in at first start.

To force regeneration:

```bash
docker exec oim-apiserver rm /tmp/Initialized.marker
docker compose -f docker-compose.oim.yml restart apiserver
```

The same applies to `oim-appserver`. Verify with:

```bash
docker exec oim-apiserver grep AppServerConnection /var/www/web.config
```

## Git hygiene

`.gitignore` excludes the actual secret files (everything in `secrets/` except
the `.example` and `.README` templates). Do not remove those rules.
