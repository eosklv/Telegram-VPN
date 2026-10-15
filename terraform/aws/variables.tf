variable "region" {
  description = "AWS region for the VPN server"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "EC2 instance type, must be arm64 to match the AMI"
  type        = string
  default     = "t4g.nano"
}

variable "ssh_key_name" {
  description = "EC2 key pair name; null disables key-based SSH"
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach SSH; empty keeps port 22 closed"
  type        = list(string)
  default     = []
}

variable "protocol" {
  description = "VPN protocol: wireguard or openvpn"
  type        = string
  default     = "wireguard"
}

variable "wireguard_peers" {
  description = "WireGuard client names, one profile and QR code per name"
  type        = list(string)
  default     = ["phone", "laptop"]
}

variable "profile_upload" {
  description = "Presigned S3 POST (url and form fields) for uploading client profiles"
  type = object({
    url    = string
    fields = map(string)
  })
  default   = null
  sensitive = true
}
