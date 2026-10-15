output "instance_public_ip" {
  description = "Public IP of the VPN server"
  value       = yandex_vpc_address.vpn_server.external_ipv4_address[0].address
}

output "vpn_endpoint" {
  description = "VPN port and transport"
  value       = "${module.cloud_init.port}/${module.cloud_init.transport}"
}
