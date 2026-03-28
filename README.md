# Satisfactory Dedicated Server on OpenStack

Deploys a [Satisfactory](https://www.satisfactorygame.com/) dedicated server on an OpenStack cloud using [OpenTofu](https://opentofu.org/). Terraform state is stored remotely in a GitLab HTTP backend.

## What it creates

- Private network, subnet, and router connected to the external network
- Security group with ports for SSH (22), game (7777 TCP/UDP), beacon (15000 UDP), query (15777 UDP), and reliable messaging (8888 TCP)
- Compute instance with the Satisfactory server installed via SteamCMD
- Floating IP associated to the instance

## Prerequisites

- OpenTofu installed
- An OpenStack project with a key pair already uploaded
- A GitLab project with a **Maintainer**-role Project Access Token (`api` scope) for remote state

## Setup

**1. Configure credentials**

Copy `.env.example` to `.env` and fill in your values:

```sh
# OpenStack
OS_AUTH_URL=https://your-cloud:13000
OS_PROJECT_NAME=...
OS_USERNAME=...
OS_PASSWORD=...
OS_USER_DOMAIN_NAME=Default
OS_PROJECT_DOMAIN_NAME=Default

# GitLab state backend
GITLAB_PROJECT_URL=https://gitlab.example.com/user/repo
GITLAB_PROJECT_ACCESS_TOKEN=...
TF_STATE_NAME=satisfactory
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

## Usage

**Deploy**

```sh
bash init.sh
```

Runs `tofu init → plan → apply`, prompts for confirmation, then streams the installation log until the server is ready.

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

The server runs as a systemd service (`satisfactory.service`) and starts automatically on boot.
