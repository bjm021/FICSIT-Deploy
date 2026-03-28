output "floating_ip" {
  description = "Public IP address of the Satisfactory server"
  value       = openstack_networking_floatingip_v2.satisfactory.address
}

output "instance_id" {
  description = "OpenStack instance UUID"
  value       = openstack_compute_instance_v2.satisfactory.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh ubuntu@${openstack_networking_floatingip_v2.satisfactory.address}"
}

output "game_address" {
  description = "Address to enter in Satisfactory's server browser"
  value       = "${openstack_networking_floatingip_v2.satisfactory.address}:7777"
}
