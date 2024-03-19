output "instance_public_ip" {
  description = "Public IP of the VPN server"
  value       = aws_instance.vpn_server.public_ip
}