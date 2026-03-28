terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }

  backend "http" {
    address        = "https://code.fbi.h-da.de/api/v4/projects/stbemeyer%2Ffactorygameserver/terraform/state/factorygameserver"
    lock_address   = "https://code.fbi.h-da.de/api/v4/projects/stbemeyer%2Ffactorygameserver/terraform/state/factorygameserver/lock"
    unlock_address = "https://code.fbi.h-da.de/api/v4/projects/stbemeyer%2Ffactorygameserver/terraform/state/factorygameserver/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
    # Credentials are injected via TF_HTTP_USERNAME / TF_HTTP_PASSWORD env vars
    # (set by sourcing env.sh — never hardcoded here)
  }
}

provider "openstack" {
  # Reads auth from clouds.yaml (public config) merged with secure.yaml (credentials).
  # Place both files in the same directory as this config, or in
  # ~/.config/openstack/. The cloud name "openstack" matches the key in both files.
  cloud = "openstack"
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------

resource "openstack_networking_secgroup_v2" "satisfactory" {
  name        = "${var.instance_name}-sg"
  description = "Security group for Satisfactory Dedicated Server"
}

# Satisfactory game traffic (UDP)
resource "openstack_networking_secgroup_rule_v2" "game_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 7777
  port_range_max    = 7777
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.satisfactory.id
  description       = "Satisfactory game port (UDP)"
}

# Satisfactory game traffic (TCP — used for some client connections)
resource "openstack_networking_secgroup_rule_v2" "game_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 7777
  port_range_max    = 7777
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.satisfactory.id
  description       = "Satisfactory game port (TCP)"
}

# Beacon port
resource "openstack_networking_secgroup_rule_v2" "beacon_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 15000
  port_range_max    = 15000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.satisfactory.id
  description       = "Satisfactory beacon port"
}

# Query port
resource "openstack_networking_secgroup_rule_v2" "query_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 15777
  port_range_max    = 15777
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.satisfactory.id
  description       = "Satisfactory query port"
}

# Reliable messaging port (required since 1.0)
resource "openstack_networking_secgroup_rule_v2" "reliable_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8888
  port_range_max    = 8888
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.satisfactory.id
  description       = "Satisfactory reliable messaging port"
}

# SSH access
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.satisfactory.id
  description       = "SSH access"
}

# ---------------------------------------------------------------------------
# Floating IP
# ---------------------------------------------------------------------------

resource "openstack_networking_floatingip_v2" "satisfactory" {
  pool = var.external_network_name
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

resource "openstack_compute_instance_v2" "satisfactory" {
  name            = var.instance_name
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = var.key_pair_name
  security_groups = [openstack_networking_secgroup_v2.satisfactory.name]

  network {
    name = var.internal_network_name
  }

  user_data = templatefile("${path.module}/userdata.sh", {
    steam_user = var.steam_anonymous ? "anonymous" : var.steam_username
  })

  metadata = {
    project = "satisfactory-server"
  }
}

resource "openstack_compute_floatingip_associate_v2" "satisfactory" {
  floating_ip = openstack_networking_floatingip_v2.satisfactory.address
  instance_id = openstack_compute_instance_v2.satisfactory.id
}
