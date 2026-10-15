output "instance_public_ip" {
  description = "Public IP of the VPN server"
  value       = aws_eip.vpn_server.public_ip
}

output "vpn_endpoint" {
  description = "VPN port and transport"
  value       = "${module.cloud_init.port}/${module.cloud_init.transport}"
}
