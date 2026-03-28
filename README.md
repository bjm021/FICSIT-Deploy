# Satisfactory Dedicated Server on OpenStack

Deploys a [Satisfactory](https://www.satisfactorygame.com/) dedicated server on an OpenStack cloud using [OpenTofu](https://opentofu.org/). Terraform state is stored remotely in a GitLab HTTP backend. World saves are backed up hourly to Cloudflare R2.

## What it creates

- Private network, subnet, and router connected to the external network
- Security group with ports for SSH (22), game (7777 TCP/UDP), beacon (15000 UDP), query (15777 UDP), and reliable messaging (8888 TCP)
- Networking port with the security group attached
- Floating IP associated to the instance
- Compute instance with the Satisfactory server installed via SteamCMD

On first boot the instance also:
- Claims the server (sets its name and admin password) via the server's HTTPS API
- Configures hourly save backups to Cloudflare R2 (keeps the 3 most recent)

## Prerequisites

- [OpenTofu](https://opentofu.org/) installed locally
- `python3` available locally (used for credential validation in `init.sh`)
- An OpenStack project with a key pair already uploaded
- A GitLab project with a **Maintainer**-role Project Access Token (`api` scope) for remote state
- A [Cloudflare R2](https://www.cloudflare.com/developer-platform/r2/) bucket with an API token (Object Read & Write, scoped to the bucket)

## Setup

**1. Configure credentials**

Copy `.env.example` to `.env` and fill in your values:

```sh
# Satisfactory server
SF_ADMIN_PASSWORD=your_strong_password

# Cloudflare R2 — Account ID from the R2 dashboard, keys from "Manage R2 API Tokens"
R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET_NAME=satisfactory-backups
R2_JURISDICTION=    # leave empty for standard, set to "eu" for EU-jurisdiction buckets

# GitLab state backend — token needs Maintainer role and "api" scope
GITLAB_PROJECT_URL=https://gitlab.example.com/user/repo
GITLAB_PROJECT_ACCESS_TOKEN=
TF_STATE_NAME=satisfactory

# OpenStack
OS_AUTH_URL=https://your-cloud:13000
OS_AUTH_TYPE=v3applicationcredential
OS_APPLICATION_CREDENTIAL_ID=
OS_APPLICATION_CREDENTIAL_SECRET=
OS_REGION_NAME=eu-central
OS_INTERFACE=public
OS_IDENTITY_API_VERSION=3
```

**2. Configure infrastructure variables**

Copy `terraform.tfvars.example` to `terraform.tfvars` and adjust:

| Variable | Description |
|---|---|
| `instance_name` | Name of the compute instance |
| `image_id` | UUID of the OS image (Ubuntu 22.04 recommended) |
| `flavor_name` | Flavor with at least 4 vCPUs / 16 GB RAM |
| `key_pair_name` | Name of your OpenStack key pair |
| `subnet_cidr` | CIDR for the private subnet |
| `external_network_name` | Name of the external floating-IP pool |
| `ssh_allowed_cidr` | CIDR allowed to reach SSH — restrict to your IP |
| `steam_anonymous` | `true` to download via anonymous Steam login (recommended) |
| `sf_server_name` | Display name shown in the server browser |

Sensitive variables (`sf_admin_password`, `r2_*`) are read from `.env` automatically — do not put them in `terraform.tfvars`.

## Usage

**Deploy**

```sh
bash init.sh
```

1. Validates all credentials (including a live R2 bucket access check) before doing anything
2. Runs `tofu init → plan → apply`, prompts for confirmation
3. Streams the installation log until the server bootstrap is complete

**Destroy**

```sh
bash destroy.sh
```

Runs `tofu plan -destroy`, prompts for confirmation, then tears down all resources.

## Connecting

Once deployed, the outputs show the server address:

```sh
tofu output game_address   # add this in Satisfactory's server browser
tofu output ssh_command    # SSH into the instance
```

The first time you connect via the game client you will be prompted to log in with the admin password set in `SF_ADMIN_PASSWORD`.

## Backups

World saves are backed up automatically every hour to `r2://<bucket>/<timestamp>/`. Only the 3 most recent backups are kept. You can check backup logs on the server with:

```sh
journalctl -u satisfactory-backup
```

To trigger a manual backup:

```sh
systemctl start satisfactory-backup
```

## Systemd services

| Service | Description |
|---|---|
| `satisfactory.service` | Game server — starts on boot, restarts on failure |
| `satisfactory-claim.service` | One-shot — claims the server on first boot |
| `satisfactory-backup.timer` | Triggers `satisfactory-backup.service` hourly |
