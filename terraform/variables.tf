variable "ami_id" {
  description = "Canonical, Ubuntu, 22.04 LTS, arm64 jammy image build on 2024-03-01"
  default     = "ami-0000456e99b2b6a9d"
}

variable "default_vpc_id" {
  description = "Default VPC"
  default     = "vpc-05ad61cf37d2a7d5f"
}

variable "default_bucket" {
  description = "S3 bucket"
  default     = "esklv-vpn"
}

variable "my_ips" {
  type    = list(string)
  default = ["45.9.230.8/32"]
}

variable "scripts_repo_url" {
  description = "Git repo link for scripts"
  default     = "https://raw.githubusercontent.com/esklv/vpn/main/scripts/"
}

variable "scripts_list" {
  description = "List of scripts"
  default     = ["server_init.sh", "ca_build.sh", "req_gen.sh", "ca_sign.sh", "ovpn_cfg.sh"]
}