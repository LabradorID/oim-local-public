# `setups/`

Drop-zone for transport packages, SQL scripts, or other artefacts you want to
import into your OneIM environment after the initial install.

This folder is intentionally empty in the public repo. Add subfolders such as:

- `01_create_test_users/` — a transport package + script to import it
- `02_other_tasks/` — additional setup automation

These are not required to run any of the make targets in this repository.

## `Local_LDAP_Example_Setup.png`

Example LDAP connection page from the Synchronization Editor, for the
Example Inc. LDAP server (`make start-ldap`).

> **Use `oimhost`, not `localhost`, as the server.** The screenshot shows
> `localhost`, which is outdated. The connection test passes with it because
> the Synchronization Editor runs on your machine, but the sync itself runs in
> the `oim-syncserver` container, where `localhost` is the container and the
> sync fails. Enter `oimhost` and port `1389` (or `2389` for the Partner GmbH
> server). See [Networking](../README.md#networking) in the main README.
