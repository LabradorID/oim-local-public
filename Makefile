.PHONY: help start-sqlinstall stop-sqlinstall restart-sqlinstall logs status connection-info clean clean-volumes clean-all backup restore shell prepare-server push-image push-image-remote start-oim stop-oim stop-down-oim fresh-start-oim export-state start-registry clean-registry snapshot list-snapshots rollback start-data build-data stop-data logs-data start-scim stop-scim logs-scim seed-scim seed-scim-generate start-ldap stop-ldap logs-ldap seed-ldap start-ldap2 stop-ldap2 logs-ldap2 seed-ldap2 stop-all

# Registry configuration
LOCAL_REGISTRY := localhost:5000
# Set REMOTE_REGISTRY in your environment or pass on the command line, e.g.:
#   make push-image-remote REMOTE_REGISTRY=yourdockerhubuser TAG=v1
REMOTE_REGISTRY ?=
IMAGE_NAME := oim10-mssql-ready

# Name the stack is reached by from the host, WSL and the containers (README "Networking").
# Read from HOST_IP in .env, defaults to oimhost.
OIM_HOST ?= $(or $(shell grep -E '^HOST_IP=' .env 2>/dev/null | cut -d= -f2),oimhost)

# Default target
help:
	@echo "One Identity Manager Docker Environment - Available Commands:"
	@echo ""
	@echo "  --- Initial database installation (run Configuration Wizard against this) ---"
	@echo "  make start-sqlinstall   - Start empty MSSQL + DB Agent for OIM Config Wizard"
	@echo "  make stop-sqlinstall    - Stop the install-mode MSSQL container"
	@echo "  make restart-sqlinstall - Restart the install-mode MSSQL container"
	@echo ""
	@echo "  --- Capture installed state into a reusable image ---"
	@echo "  make start-registry     - Start local Docker registry on :5000"
	@echo "  make export-state       - Export full SQL Server state from a running container"
	@echo "  make push-image         - Build full-state image and push to LOCAL registry"
	@echo "  make push-image-remote  - Build full-state image and push to a REMOTE registry"
	@echo "  make clean-registry     - Remove the local registry and stored images"
	@echo ""
	@echo "  --- Failsafe development (snapshot & rollback) ---"
	@echo "  make snapshot TAG=v02_Feature_ready  - Snapshot running OneIM DB to a new tag"
	@echo "  make list-snapshots                  - List snapshot tags in the local registry"
	@echo "  make rollback TAG=v01                - Switch active image tag and recreate MSSQL"
	@echo ""
	@echo "  --- Ready environment (uses image you built above) ---"
	@echo "  make start-oim          - Start/resume full OIM environment (mssql, dbagent, jobserver, syncserver, appserver, apiserver)"
	@echo "  make fresh-start-oim    - Recreate OIM environment from scratch"
	@echo "  make stop-oim           - Stop OIM environment (keeps data)"
	@echo "  make stop-down-oim      - Stop and remove OIM containers (data is lost)"
	@echo "  make logs               - Follow OIM container logs"
	@echo "  make status             - Show container status and resource usage"
	@echo "  make connection-info    - Show SQL Server / Job Server connection details"
	@echo "  make shell              - Open a sqlcmd shell against the install-mode container"
	@echo ""
	@echo "  --- Optional data services (SCIM + 2x LDAP) ---"
	@echo "  make start-data         - Start SCIM + both LDAP servers on the OIM network"
	@echo "  make build-data         - Rebuild and start data services"
	@echo "  make stop-data          - Stop data services"
	@echo "  make logs-data          - Follow data services logs"
	@echo "  make start-scim / stop-scim / logs-scim"
	@echo "  make seed-scim          - Seed SCIM with the bundled test users"
	@echo "  make seed-scim-generate COUNT=1000 - Generate N random SCIM users"
	@echo "  make start-ldap / stop-ldap / logs-ldap / seed-ldap   - Example Inc. LDAP"
	@echo "  make start-ldap2 / stop-ldap2 / logs-ldap2 / seed-ldap2 - Partner GmbH LDAP"
	@echo ""
	@echo "  --- Backup / cleanup ---"
	@echo "  make backup             - Create a OneIM database backup"
	@echo "  make restore BACKUP_FILE=path/to.bak - Restore from backup"
	@echo "  make stop-all           - Stop everything (keeps data)"
	@echo "  make clean              - Remove containers (keeps volumes/data)"
	@echo "  make clean-volumes      - Remove containers AND volumes (deletes all data)"
	@echo "  make clean-all          - Remove everything including images"
	@echo ""

# Start the MSSQL database container (setup mode)
start-sqlinstall:
	@echo "Starting MSSQL database (setup mode)..."
	docker compose -f docker-compose.sqlinstall.yml up -d
	@echo "Waiting for database to be healthy..."
	@timeout 60 sh -c 'until docker compose -f docker-compose.sqlinstall.yml ps | grep -q "healthy"; do sleep 2; done' || true
	@echo "Database is ready! Now run the One Identity Manager Configuration Wizard"
	@echo "and point it at this server. See README.md for prerequisites."

# Stop the MSSQL database container
stop-sqlinstall:
	@echo "Stopping MSSQL database..."
	docker compose -f docker-compose.sqlinstall.yml stop

# Restart the MSSQL database container
restart-sqlinstall:
	@echo "Restarting MSSQL database..."
	docker compose -f docker-compose.sqlinstall.yml restart

# Start OIM environment (resumes existing containers, keeps data)
start-oim:
	@echo "Ensuring local registry is running..."
	@$(MAKE) -s start-registry
	@echo ""
	@echo "Starting OneIM environment..."
	docker compose -f docker-compose.oim.yml start 2>/dev/null || docker compose -f docker-compose.oim.yml up -d
	@echo "Waiting for database to be healthy..."
	@timeout 60 sh -c 'until docker compose -f docker-compose.oim.yml ps | grep -q "healthy"; do sleep 2; done' || true
	@echo "OneIM environment is ready."

# Start fresh OIM environment (recreates containers from image)
fresh-start-oim:
	@echo "Ensuring local registry is running..."
	@$(MAKE) -s start-registry
	@echo ""
	@echo "Recreating OneIM environment from scratch..."
	docker compose -f docker-compose.oim.yml down
	docker compose -f docker-compose.oim.yml up -d
	@echo "Waiting for database to be healthy..."
	@timeout 60 sh -c 'until docker compose -f docker-compose.oim.yml ps | grep -q "healthy"; do sleep 2; done' || true
	@echo "OneIM environment is ready (fresh from image)."

# Stop OIM environment (stops containers, keeps data)
stop-oim:
	@echo "Stopping OneIM environment (keeping containers)..."
	docker compose -f docker-compose.oim.yml stop
	@echo "Environment stopped. Run 'make start-oim' to resume."

# Stop and remove OIM containers (data is lost)
stop-down-oim:
	@echo "Stopping and removing OneIM environment..."
	docker compose -f docker-compose.oim.yml down
	@echo "Environment removed. Run 'make fresh-start-oim' to start clean."

# Start data services (SCIM + LDAP) on OIM network
start-data:
	@echo "Starting data services (SCIM + LDAP)..."
	docker compose -f docker-compose.dataservices.yml up -d
	@echo ""
	@echo "Data services are running!"
	@echo "  SCIM:    http://$(OIM_HOST):8585"
	@echo "  LDAP:    ldap://$(OIM_HOST):1389  (Example Inc.)"
	@echo "  LDAP 2:  ldap://$(OIM_HOST):2389  (Partner GmbH)"

# Rebuild and start data services
build-data:
	@echo "Rebuilding and starting data services (SCIM + LDAP)..."
	docker compose -f docker-compose.dataservices.yml up -d --build
	@echo ""
	@echo "Data services rebuilt and running."

# Stop data services
stop-data:
	@echo "Stopping data services..."
	docker compose -f docker-compose.dataservices.yml stop
	@echo "Data services stopped."

# View data services logs
logs-data:
	docker compose -f docker-compose.dataservices.yml logs -f

# View logs
logs:
	docker compose -f docker-compose.oim.yml logs -f

# Show status
status:
	@echo "=== OIM Container Status ==="
	@docker compose -f docker-compose.oim.yml ps 2>/dev/null || true
	@echo ""
	@echo "=== Data Services Status ==="
	@docker compose -f docker-compose.dataservices.yml ps 2>/dev/null || true
	@echo ""
	@echo "=== Resource Usage ==="
	docker stats --no-stream

# Show connection information
connection-info:
	@echo "=== SQL Server Connection Information ==="
	@echo ""
	@echo "For SSMS or Azure Data Studio:"
	@echo "  Server:         $(OIM_HOST),1433"
	@echo "  Authentication: SQL Server Authentication"
	@echo "  Login:          sa"
	@echo "  Password:       $$(grep MSSQL_SA_PASSWORD .env | cut -d '=' -f2)"
	@echo "  Trust Cert:     Yes"
	@echo ""
	@echo "=== Job Server Web Frontend ==="
	@echo "  URL:      http://$(OIM_HOST):1880"
	@echo "  Username: $$(grep JOBSERVER_HTTP_USER .env 2>/dev/null | cut -d '=' -f2 || echo 'admin')"
	@echo "  Password: $$(grep JOBSERVER_HTTP_PWD .env 2>/dev/null | cut -d '=' -f2 || echo 'Password123')"
	@echo ""
	@echo "=== App Server / API Server ==="
	@echo "  AppServer: http://$(OIM_HOST):8080"
	@echo "  APIServer: http://$(OIM_HOST):8182"
	@echo ""
	@echo "Note: the host, WSL and the containers all use '$(OIM_HOST)' (see README, Networking)."

# Open SQL shell against install-mode container
shell:
	@echo "Opening sqlcmd against oim10-mssql..."
	docker exec -it oim10-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$$(grep MSSQL_SA_PASSWORD .env | cut -d '=' -f2)" -C

# Create backup (against the ready environment)
backup:
	@echo "Creating database backup..."
	@mkdir -p backups
	@docker exec -u root oim10-mssql-ready chown -R mssql:root /var/opt/mssql/backup 2>/dev/null || true
	@docker exec -u root oim10-mssql-ready chmod -R 775 /var/opt/mssql/backup 2>/dev/null || true
	docker exec oim10-mssql-ready /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$$(grep MSSQL_SA_PASSWORD .env | cut -d '=' -f2)" -C -Q "BACKUP DATABASE OneIM TO DISK='/var/opt/mssql/backup/OneIM_$$(date +%Y%m%d_%H%M%S).bak' WITH FORMAT, COMPRESSION"
	@echo "Backup completed."

# Restore backup (usage: make restore BACKUP_FILE=path/to/backup.bak)
restore:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE variable required"; \
		echo "Usage: make restore BACKUP_FILE=path/to/backup.bak"; \
		exit 1; \
	fi
	@echo "Copying backup to container..."
	docker cp $(BACKUP_FILE) oim10-mssql-ready:/var/opt/mssql/backup/restore.bak
	@echo "Restoring database..."
	docker exec -it oim10-mssql-ready /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$$(grep MSSQL_SA_PASSWORD .env | cut -d '=' -f2)" -C -Q "RESTORE DATABASE OneIM FROM DISK='/var/opt/mssql/backup/restore.bak' WITH REPLACE"
	@echo "Database restored."

# Start local Docker registry
start-registry:
	@echo "Starting local Docker registry on port 5000..."
	@if docker ps -q -f name=oim-registry | grep -q .; then \
		echo "Registry already running."; \
	elif docker ps -aq -f name=oim-registry | grep -q .; then \
		docker start oim-registry; \
	else \
		docker run -d -p 5000:5000 --name oim-registry -v oim-public_registry-data:/var/lib/registry -e REGISTRY_STORAGE_DELETE_ENABLED=true registry:2; \
	fi
	@echo "Local registry running at localhost:5000"
	@echo ""
	@echo "List images: curl -s http://localhost:5000/v2/_catalog | jq"

# Export full SQL Server state from running container (usage: make export-state CONTAINER=oim10-mssql)
export-state:
	@CONTAINER=$${CONTAINER:-oim10-mssql}; \
	echo "Exporting full SQL Server state from container: $$CONTAINER"; \
	echo "Captures all databases including master (logins), model, msdb, and OneIM."; \
	echo ""; \
	echo "Stopping SQL Server gracefully..."; \
	docker exec $$CONTAINER /opt/mssql/bin/sqlservr --stop 2>/dev/null || docker stop $$CONTAINER; \
	echo ""; \
	echo "Copying SQL Server data directory..."; \
	rm -rf mssql-state; \
	mkdir -p mssql-state; \
	docker cp $$CONTAINER:/var/opt/mssql/. mssql-state/; \
	echo "Fixing permissions for Docker build..."; \
	chmod -R a+r mssql-state/; \
	echo ""; \
	echo "Restarting container..."; \
	docker start $$CONTAINER; \
	echo ""; \
	echo "Export complete. State saved to ./mssql-state/"; \
	echo "Size: $$(du -sh mssql-state | cut -f1)"

# Build and push to LOCAL registry
push-image:
	@if [ -z "$(TAG)" ]; then \
		TAG="latest"; \
	fi; \
	echo "=== Building Full State SQL Server Image (Local Registry) ==="; \
	$(MAKE) start-registry; \
	if [ ! -d "mssql-state" ] || [ -z "$$(ls -A mssql-state 2>/dev/null)" ]; then \
		echo "No mssql-state directory found. Running export-state first..."; \
		$(MAKE) export-state; \
	fi; \
	echo "Building Docker image with full SQL Server state..."; \
	docker build -f Dockerfile.fullstate -t $(LOCAL_REGISTRY)/$(IMAGE_NAME):$$TAG .; \
	echo "Pushing image to local registry: $(LOCAL_REGISTRY)/$(IMAGE_NAME):$$TAG"; \
	docker push $(LOCAL_REGISTRY)/$(IMAGE_NAME):$$TAG; \
	echo "Image size: $$(docker images $(LOCAL_REGISTRY)/$(IMAGE_NAME):$$TAG --format '{{.Size}}')"; \
	echo "Cleaning up mssql-state..."; \
	rm -rf mssql-state; \
	echo "To run: make start-oim"

# Build and push to REMOTE registry (Docker Hub or other)
push-image-remote:
	@if [ -z "$(REMOTE_REGISTRY)" ]; then \
		echo "Error: REMOTE_REGISTRY is not set."; \
		echo "Usage: make push-image-remote REMOTE_REGISTRY=yourdockerhubuser TAG=v1"; \
		exit 1; \
	fi; \
	if [ -z "$(TAG)" ]; then \
		TAG="latest"; \
	fi; \
	echo "=== Building Full State SQL Server Image (Remote Registry) ==="; \
	if [ ! -d "mssql-state" ] || [ -z "$$(ls -A mssql-state 2>/dev/null)" ]; then \
		echo "No mssql-state directory found. Running export-state first..."; \
		$(MAKE) export-state; \
	fi; \
	echo "Building Docker image..."; \
	docker build -f Dockerfile.fullstate -t $(REMOTE_REGISTRY)/$(IMAGE_NAME):$$TAG .; \
	echo "Pushing image: $(REMOTE_REGISTRY)/$(IMAGE_NAME):$$TAG"; \
	docker push $(REMOTE_REGISTRY)/$(IMAGE_NAME):$$TAG; \
	echo "Cleaning up mssql-state..."; \
	rm -rf mssql-state; \
	echo "To pull: docker pull $(REMOTE_REGISTRY)/$(IMAGE_NAME):$$TAG"

# Snapshot the live OneIM database into a new tagged image (failsafe checkpoint).
# Does NOT change the active tag in .env — the running container keeps using its
# current image. Usage: make snapshot TAG=v02_Downtimer_LDAP_ready
snapshot:
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG is required."; \
		echo "Usage: make snapshot TAG=v02_Feature_ready"; \
		exit 1; \
	fi
	@$(MAKE) -s start-registry
	@if curl -sf -o /dev/null -H "Accept: application/vnd.docker.distribution.manifest.v2+json" http://localhost:5000/v2/$(IMAGE_NAME)/manifests/$(TAG); then \
		echo "Error: tag '$(TAG)' already exists in $(LOCAL_REGISTRY)/$(IMAGE_NAME)."; \
		echo "Pick a different tag, or remove it from the registry first."; \
		exit 1; \
	fi
	@CONTAINER=$${CONTAINER:-oim10-mssql-ready}; \
	if ! docker ps -q -f name=$$CONTAINER | grep -q .; then \
		echo "Error: container '$$CONTAINER' is not running."; \
		echo "Start it with 'make start-oim' (or pass CONTAINER=<name>) first."; \
		exit 1; \
	fi; \
	echo "=== Snapshotting $$CONTAINER -> $(LOCAL_REGISTRY)/$(IMAGE_NAME):$(TAG) ==="; \
	echo "Note: SQL Server will stop briefly during the copy, then restart."; \
	$(MAKE) export-state CONTAINER=$$CONTAINER; \
	$(MAKE) push-image TAG=$(TAG); \
	echo ""; \
	echo "Snapshot saved. Roll back to it later with:"; \
	echo "  make rollback TAG=$(TAG)"

# List snapshot tags in the local registry and show the active tag from .env.
list-snapshots:
	@$(MAKE) -s start-registry
	@echo "Snapshots in $(LOCAL_REGISTRY)/$(IMAGE_NAME):"
	@TAGS=$$(curl -sf http://localhost:5000/v2/$(IMAGE_NAME)/tags/list 2>/dev/null | jq -r '.tags[]?' 2>/dev/null | sort); \
	if [ -z "$$TAGS" ]; then \
		echo "  (no snapshots yet - run 'make snapshot TAG=...' to create one)"; \
	else \
		echo "$$TAGS" | sed 's/^/  /'; \
	fi
	@echo ""
	@ACTIVE=$$(grep ^MSSQL_IMAGE_TAG .env 2>/dev/null | cut -d= -f2); \
	echo "Active tag (MSSQL_IMAGE_TAG in .env): $${ACTIVE:-v01 (default)}"

# Switch the active image tag and recreate the OneIM environment from it.
# Usage: make rollback TAG=v01
rollback:
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG is required."; \
		echo "Usage: make rollback TAG=v01"; \
		echo ""; \
		$(MAKE) -s list-snapshots; \
		exit 1; \
	fi
	@$(MAKE) -s start-registry
	@if ! curl -sf -o /dev/null -H "Accept: application/vnd.docker.distribution.manifest.v2+json" http://localhost:5000/v2/$(IMAGE_NAME)/manifests/$(TAG); then \
		echo "Error: tag '$(TAG)' not found in $(LOCAL_REGISTRY)/$(IMAGE_NAME)."; \
		echo ""; \
		$(MAKE) -s list-snapshots; \
		exit 1; \
	fi
	@CURRENT=$$(grep ^MSSQL_IMAGE_TAG .env 2>/dev/null | cut -d= -f2); \
	echo "=== Rollback ==="; \
	echo "  Current MSSQL_IMAGE_TAG: $${CURRENT:-v01 (default)}"; \
	echo "  Target  MSSQL_IMAGE_TAG: $(TAG)"; \
	echo ""; \
	echo "WARNING: this recreates the MSSQL container. Any database changes made"; \
	echo "since your last snapshot will be LOST. Take a 'make snapshot' first if"; \
	echo "you want to preserve the current state."; \
	read -p "Continue? [y/N] " -n 1 -r REPLY; \
	echo ""; \
	if [ "$$REPLY" != "y" ] && [ "$$REPLY" != "Y" ]; then \
		echo "Cancelled."; \
		exit 0; \
	fi; \
	if [ ! -f .env ]; then \
		echo "MSSQL_IMAGE_TAG=$(TAG)" > .env; \
	elif grep -q ^MSSQL_IMAGE_TAG .env; then \
		sed -i.bak "s|^MSSQL_IMAGE_TAG=.*|MSSQL_IMAGE_TAG=$(TAG)|" .env && rm -f .env.bak; \
	else \
		echo "MSSQL_IMAGE_TAG=$(TAG)" >> .env; \
	fi; \
	echo "Updated .env -> MSSQL_IMAGE_TAG=$(TAG)"; \
	echo ""; \
	$(MAKE) fresh-start-oim

# Start only the SCIM server
start-scim:
	@echo "Starting SCIM server..."
	docker compose -f docker-compose.dataservices.yml up -d scimserver
	@echo ""
	@echo "SCIM server is running!"
	@echo "  URL:          http://$(OIM_HOST):8585"
	@echo "  Bearer Token: $$(grep SCIM_BEARER_TOKEN .env | cut -d '=' -f2)"

# Stop the SCIM server
stop-scim:
	@echo "Stopping SCIM server..."
	docker compose -f docker-compose.dataservices.yml stop scimserver

# View SCIM server logs
logs-scim:
	docker compose -f docker-compose.dataservices.yml logs -f scimserver

# Seed SCIM server with test users from JSON
seed-scim:
	@echo "Seeding SCIM server with test data..."
	python3 seed-scim.py --clear

# Generate N random users in SCIM server
seed-scim-generate:
	@echo "Generating $(COUNT) random users in SCIM server..."
	python3 seed-scim.py --clear --generate $(COUNT)

# Start only the LDAP server (Example Inc.)
start-ldap:
	@echo "Starting LDAP server..."
	docker compose -f docker-compose.dataservices.yml up -d ldapserver
	@echo ""
	@echo "  Host:     $(OIM_HOST)"
	@echo "  Port:     1389 (LDAP) / 1636 (LDAPS)"
	@echo "  Base DN:  dc=example,dc=com"
	@echo "  Admin DN: cn=admin,dc=example,dc=com"
	@echo "  Password: $$(grep LDAP_ADMIN_PASSWORD .env 2>/dev/null | cut -d '=' -f2 || echo 'Password123')"

stop-ldap:
	docker compose -f docker-compose.dataservices.yml stop ldapserver

logs-ldap:
	docker compose -f docker-compose.dataservices.yml logs -f ldapserver

# Re-seed LDAP server (destroys volumes)
seed-ldap:
	@echo "Re-seeding LDAP server (this destroys existing data)..."
	docker compose -f docker-compose.dataservices.yml rm -sfv ldapserver
	docker compose -f docker-compose.dataservices.yml up -d ldapserver
	@echo "LDAP server re-seeded from ldap-seed-data.ldif"

# Partner LDAP server
start-ldap2:
	@echo "Starting partner LDAP server (Partner GmbH)..."
	docker compose -f docker-compose.dataservices.yml up -d ldapserver2
	@echo ""
	@echo "  Host:     $(OIM_HOST)"
	@echo "  Port:     2389 (LDAP) / 2636 (LDAPS)"
	@echo "  Base DN:  dc=partner,dc=com"
	@echo "  Admin DN: cn=admin,dc=partner,dc=com"
	@echo "  Password: $$(grep LDAP_ADMIN_PASSWORD .env 2>/dev/null | cut -d '=' -f2 || echo 'Password123')"

stop-ldap2:
	docker compose -f docker-compose.dataservices.yml stop ldapserver2

logs-ldap2:
	docker compose -f docker-compose.dataservices.yml logs -f ldapserver2

seed-ldap2:
	@echo "Re-seeding partner LDAP server (this destroys existing data)..."
	docker compose -f docker-compose.dataservices.yml rm -sfv ldapserver2
	docker compose -f docker-compose.dataservices.yml up -d ldapserver2
	@echo "Partner LDAP server re-seeded from ldap-seed-data-partner.ldif"

# Stop everything (keeps data)
stop-all:
	@echo "Stopping all containers..."
	@docker compose -f docker-compose.sqlinstall.yml stop 2>/dev/null || true
	@docker compose -f docker-compose.oim.yml stop 2>/dev/null || true
	@docker compose -f docker-compose.dataservices.yml stop 2>/dev/null || true
	@docker stop oim-registry 2>/dev/null || true
	@echo "All containers stopped. Data preserved."

# Clean up containers (keeps data)
clean:
	@echo "Stopping and removing containers..."
	docker compose -f docker-compose.sqlinstall.yml down 2>/dev/null || true
	docker compose -f docker-compose.oim.yml down 2>/dev/null || true
	docker compose -f docker-compose.dataservices.yml down 2>/dev/null || true
	@echo "Cleanup complete. Data volumes preserved."

# Clean up volumes (deletes all data)
clean-volumes:
	@echo "WARNING: This will delete all database data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		echo "Removing containers and volumes..."; \
		docker compose -f docker-compose.sqlinstall.yml down -v 2>/dev/null || true; \
		docker compose -f docker-compose.oim.yml down -v 2>/dev/null || true; \
		docker compose -f docker-compose.dataservices.yml down -v 2>/dev/null || true; \
		echo "All data deleted."; \
	else \
		echo "Cancelled."; \
	fi

# Complete cleanup (removes everything)
clean-all:
	@echo "WARNING: This will remove containers, volumes, and images!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		echo "Removing everything..."; \
		docker compose -f docker-compose.sqlinstall.yml down -v --rmi all 2>/dev/null || true; \
		docker compose -f docker-compose.oim.yml down -v --rmi all 2>/dev/null || true; \
		docker compose -f docker-compose.dataservices.yml down -v --rmi all 2>/dev/null || true; \
		echo "Complete cleanup finished."; \
	else \
		echo "Cancelled."; \
	fi

# Remove registry container and its volume
clean-registry:
	@echo "Removing local Docker registry and all stored images..."
	@docker rm -f oim-registry 2>/dev/null || true
	@docker volume rm oim-public_registry-data 2>/dev/null || true
	@echo "Registry cleaned. Run 'make start-registry' to create a fresh one."
