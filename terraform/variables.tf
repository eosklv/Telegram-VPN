variable "ami_id" {
  description = "Canonical, Ubuntu, 22.04 LTS, arm64 jammy image build on 2024-03-01"
  default     = "ami-0000456e99b2b6a9d"
}

variable "default_vpc_id" {
  description = "Default VPC"
  default     = "vpc-05ad61cf37d2a7d5f"
}

variable "bucket_access_role_arn" {
  description = "Policy to access S3"
  default     = "arn:aws:iam::905418258334:policy/esklv-vpnS3FullAccess"
}

variable "default_bucket" {
  description = "S3 bucket"
  default     = "esklv-vpn"
}

variable "my_ips" {
  type    = list(string)
  default = ["45.9.230.8/32"]
}