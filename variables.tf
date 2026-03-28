variable "instance_name" {
  description = "Name of the compute instance"
  type        = string
  default     = "satisfactory-server"
}

variable "image_id" {
  description = "OS image UUID."
  type        = string
}

variable "flavor_name" {
  description = <<-EOT
    OpenStack flavor for the instance.
    Satisfactory recommends at least 4 vCPUs and 16 GB RAM for a comfortable
    multiplayer experience. Adjust to match your cloud provider's flavor catalogue.
  EOT
  type        = string
  default     = "c4.xlarge"  # 4 vCPU / 16 GB — rename to match your cloud
}

variable "key_pair_name" {
  description = "Name of the OpenStack key pair to inject for SSH access"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR for the private subnet Terraform creates for the server"
  type        = string
  default     = "10.10.10.0/24"
}

variable "external_network_name" {
  description = "Name of the external/floating-IP pool (e.g. 'public', 'ext-net')"
  type        = string
  default     = "public"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to reach port 22. Restrict this to your own IP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "steam_anonymous" {
  description = "Use Steam anonymous login to download the server (recommended — no Steam account needed)"
  type        = bool
  default     = true
}

variable "steam_username" {
  description = "Steam username (only used when steam_anonymous = false)"
  type        = string
  default     = ""
}
