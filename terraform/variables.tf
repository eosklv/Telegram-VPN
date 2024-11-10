variable "ami_id" {
  description = "Canonical, Ubuntu, 22.04 LTS, arm64 jammy image build on 2024-03-01"
  default     = "ami-0dcbfe330b31195ff"
}

variable "default_vpc_id" {
  description = "Default VPC"
  default     = "vpc-040830449b6066fb3"
}

variable "bucket_access_role_arn" {
  description = "Policy to access S3"
  default     = "arn:aws:iam::905418258334:policy/esklv-vpnS3FullAccess"
}

variable "default_bucket" {
  description = "S3 bucket"
  default     = "esklv-vpn-eu-north-1"
}
