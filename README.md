# One Identity Manager — Local Docker Environment

A Docker Compose setup for running [One Identity Manager (OIM)](https://www.oneidentity.com/products/identity-manager/)
locally for development, testing, and learning. It covers:

1. Bringing up an empty MSSQL server so the OIM **Configuration Wizard** can
   create the OneIM database schema.
2. Capturing that installed state into a reusable Docker image stored in a
   local Docker registry.
3. Running the full "ready" environment (MSSQL + DB Agent + Job Server +
   Sync Server + App Server + API Server) from that image.
4. Optional auxiliary data services: a SCIM 2.0 server and two OpenLDAP
   directories with seed data, useful as synchronisation targets.

> **Heads up:** this repository ships *only* compose files, Dockerfiles, and
> seed data. **It does not include any One Identity software.**

---

## Prerequisites

You **must** obtain the following yourself before any of this is useful:

- **Valid One Identity Manager installation media (v10.x).** OIM is licensed
  commercial software from One Identity. This repo cannot bundle it.
  Download it from the One Identity support portal with a valid contract.
- The **Configuration Wizard** from those sources (typically run from a
  Windows machine that can reach the MSSQL container on port 1433).
- A working Docker engine with Compose v2, ~30 GB free disk space, and
  GNU `make`.
- (Windows + WSL) `hostname -I` should report a routable IP for the WSL host;
  Windows clients connect to that IP, not `localhost`.
- Make sure make and docker are installed on your machine

The OIM container images (`oneidentity/oneim-dbagent`, `oneidentity/oneim-job`,
`oneidentity/oneim-appserver`, `oneidentity/oneim-api`) are public on Docker Hub
and pulled automatically — no licence key is needed to pull them, but you still
need a OneIM database (i.e. step 1 below) for them to work against.

---

## Quick start

```bash
git clone <this-repo>
cd <this-repo>
cp .env.example .env
$EDITOR .env                # set MSSQL_SA_PASSWORD etc.
```

Then follow the three flows in order.

---

## Flow 1 — Initial database installation

Goal: produce an empty OneIM database that the OIM Configuration Wizard has
populated with the schema.

```bash
make start-sqlinstall
```

This brings up:

- `oim10-mssql` — a stock `mcr.microsoft.com/mssql/server:2022-latest`
  with `MSSQL_COLLATION=Latin1_General_CI_AS` (case-insensitive — required by
  the Wizard).
- `oim-dbagent` — the OIM DBQueue processor.

> SQL Server **must be case-insensitive** for the Configuration Wizard to run.
> The `docker-compose.sqlinstall.yml` already sets this; do not change it.

Now, on the machine where the OIM sources are installed, launch the
**Configuration Wizard** and point it at the SQL Server:

- Server: `<host IP>,1433`
- Auth: SQL Server Authentication
- Login: `sa`
- Password: the value you set in `.env` (`MSSQL_SA_PASSWORD`)
- Trust server certificate: yes

Let the Wizard create the OneIM database, the DB user accounts (e.g.
`OneIM_Admin`, `OneIM_Config`, `OneIM_User` but you can skip the config and user for database access as for the local setup we can start with the admin), and the OneIM system user
(`viadmin` etc.). You can easily use the same password for all. 

When the Wizard finishes successfully and the DB Agent has worked through the
initial DBQueue, you have a usable OneIM database living inside the container's
volume.

To stop:

```bash
make stop-sqlinstall
```

---

## Flow 2 — Capture state into an image (local registry)

Goal: package the populated MSSQL data directory into a Docker image so you
can spin up a fresh, fully-installed OIM database in seconds.

```bash
make start-registry                       # localhost:5000 Docker registry
make export-state CONTAINER=oim10-mssql   # snapshot /var/opt/mssql
make push-image TAG=v01                   # builds Dockerfile.fullstate, pushes
```

What this does:

1. Stops the SQL Server inside `oim10-mssql` cleanly, copies the entire
   `/var/opt/mssql` data directory to `./mssql-state/`, and restarts the
   container.
2. Builds an image from `Dockerfile.fullstate` that bakes that data directory
   into a fresh `mcr.microsoft.com/mssql/server:2022-latest`.
3. Pushes it to `localhost:5000/oim10-mssql-ready:v01`.

Inspect the registry:

```bash
curl -s http://localhost:5000/v2/_catalog | jq
curl -s http://localhost:5000/v2/oim10-mssql-ready/tags/list | jq
```

To push to a remote registry instead (e.g. your own Docker Hub repo):

```bash
make push-image-remote REMOTE_REGISTRY=yourdockerhubuser TAG=v01
```

> **Do not push images containing customer data, real credentials, or
> proprietary One Identity content to public registries.** A snapshot of an
> installed OneIM database may include hashed system-user passwords and the
> trusted-source key. Treat it as sensitive.

---

## Flow 3 — Run the ready OIM environment

Goal: start the full OIM stack against the image you just built.

`docker-compose.oim.yml` references `localhost:5000/oim10-mssql-ready:v01` by
default. If you used a different tag or registry, edit the `image:` field of
the `mssql` service before continuing.

The secret files under `secrets/apiserver/` and `secrets/appserver/` are
committed with ready-to-use **local-dev** values that match the defaults in
`.env.example`. 
**Note** replace the localhost urls with the hostname ip address of your machine
The only thing you still have to provide yourself is the
session certificate:

```bash
# Generate a self-signed certificate and drop it into both folders.
openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/cert.pem \
    -days 3650 -nodes -subj "/CN=oim-apiserver"
openssl pkcs12 -export -out secrets/apiserver/SessionCertificate.pfx \
    -inkey /tmp/key.pem -in /tmp/cert.pem -passout pass:
cp secrets/apiserver/SessionCertificate.pfx secrets/appserver/SessionCertificate.pfx
```

If you connect from a different host (e.g. Windows talking to a WSL host),
edit `secrets/apiserver/APPSERVERCONNSTRING` so the `Url=` value matches the
host IP that the portal session uses (see
[`secrets/README.md`](secrets/README.md) for details).

Then bring it up:

```bash
make fresh-start-oim     # first run (fresh from image)
# or
make start-oim           # resume previously created containers
```

What's running:

| Service       | Container             | Port  | Purpose                                |
|---------------|-----------------------|-------|----------------------------------------|
| MSSQL         | `oim10-mssql-ready`   | 1433  | Pre-populated OneIM database           |
| DB Agent      | `oim-dbagent`         | —     | DBQueue processor                      |
| Job Server    | `oim-jobserver`       | 1880  | Default `\MSSQL` queue                 |
| Sync Server   | `oim-syncserver`      | 1881  | `\SYNCSERVER1` queue                   |
| App Server    | `oim-appserver`       | 8080  | OIM Application Server                 |
| API Server    | `oim-apiserver`       | 8182  | OIM API Server / portals               |

```bash
make connection-info    # prints SSMS, Job Server, App/API URLs
make logs               # follow combined logs
make stop-oim           # stop, keep data
make stop-down-oim      # stop and remove containers (data lost)
```

To save changes back to the image after working in the environment:

```bash
make export-state CONTAINER=oim10-mssql-ready
make push-image TAG=v02   # bump the tag, then update docker-compose.oim.yml
```

---

## Optional — SCIM and LDAP data services

The data services compose file ships a SCIM 2.0 server and two OpenLDAP
directories you can use as synchronisation sources/targets in OIM.

```bash
make start-data        # both LDAPs + SCIM
# or individually:
make start-scim        # SCIM at :8585
make start-ldap        # Example Inc.   ldap://<host>:1389
make start-ldap2       # Partner GmbH   ldap://<host>:2389

make seed-scim                           # bundled test users from scim-seed-data.json
make seed-scim-generate COUNT=1000       # generate N random users
make seed-ldap                           # destroy + reseed Example Inc. LDAP
make seed-ldap2                          # destroy + reseed Partner GmbH LDAP
```

The Postman collection [scim2-postman-collection.json](scim2-postman-collection.json)
is included for poking the SCIM server interactively.

These services join the `oim-network` Docker network, so containers in the
ready environment can address them by hostname (`scimserver`, `ldapserver`,
`ldapserver2`).

---

## Repository layout

| File / dir                              | What it is                                            |
|-----------------------------------------|-------------------------------------------------------|
| `docker-compose.sqlinstall.yml`         | Empty MSSQL + DB Agent for the Configuration Wizard.  |
| `docker-compose.oim.yml`                | Full ready environment (uses your built image).       |
| `docker-compose.dataservices.yml`       | Optional SCIM + 2× LDAP servers.                      |
| `Dockerfile.fullstate`                  | Bakes `mssql-state/` into a SQL Server image.         |
| `Dockerfile.scim`                       | Tiny image around `scim2-server` (Python).            |
| `oim-defaults.sql`                      | SQL applied automatically after the ready DB starts.  |
| `seed-scim.py`, `scim-seed-data.json`   | SCIM seed tool + bundled test data.                   |
| `scim2-postman-collection.json`         | Postman collection for the SCIM server.               |
| `ldap-seed-data*.ldif`                  | LDIF seed data for the two LDAP directories.          |
| `secrets/`                              | App/API Server secret files (local-dev values) — see its README. |
| `.env.example`                          | Copy to `.env` and edit before you start anything.    |
| `Makefile`                              | All targets above; run `make help` for the full list. |

---

## Troubleshooting

- **App/API Server reload doesn't pick up edited secrets.** First-run only —
  see the "Editing secrets after the first start" section in
  [secrets/README.md](secrets/README.md).
- **Portal search fails with `[810432] Die Verbindung "..." wurde in der
  Konfiguration nicht gefunden.`** Your `APPSERVERCONNSTRING` is wrong; it must
  start with `Url=` and use the same URL the portal session uses (typically
  the host IP, not `appserver`).
- **Configuration Wizard refuses to install.** SQL collation isn't
  case-insensitive. Don't change `MSSQL_COLLATION` in
  `docker-compose.sqlinstall.yml`.
- **`make export-state` / `push-image` runs out of disk.** A populated OneIM
  database is several GB; `mssql-state/` is deleted automatically after the
  image is built.

---

## Licensing

The code in this repository (compose files, Makefile, scripts, templates) is
provided as-is for development and educational use. **One Identity Manager
itself is commercial software and is not redistributed here.** You are
responsible for complying with One Identity's licence terms when running this
environment.

The `oneidentity/*` Docker images this repository pulls from Docker Hub are
published by One Identity; their terms apply.
