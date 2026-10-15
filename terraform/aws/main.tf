terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.10.0"

  # bucket and region are passed with -backend-config
  backend "s3" {
    key          = "terraform/terraform.tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "vpn"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
}

resource "aws_eip" "vpn_server" {
  domain = "vpc"

  tags = {
    Name = "vpn_server"
  }
}

module "cloud_init" {
  source = "../modules/cloud-init"

  server_ip       = aws_eip.vpn_server.public_ip
  protocol        = var.protocol
  wireguard_peers = var.wireguard_peers
  profile_upload  = var.profile_upload
}

resource "terraform_data" "server_config" {
  input = module.cloud_init.config_hash
}

resource "aws_instance" "vpn_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.vpn_server.id]

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = module.cloud_init.user_data

  tags = {
    Name = "vpn_server"
  }

  lifecycle {
    # The upload URL is regenerated on every run and new AMIs are published regularly;
    # the server is rebuilt only when its configuration changes.
    ignore_changes       = [ami, user_data]
    replace_triggered_by = [terraform_data.server_config]
  }
}

resource "aws_eip_association" "vpn_server" {
  instance_id   = aws_instance.vpn_server.id
  allocation_id = aws_eip.vpn_server.id
}

resource "aws_security_group" "vpn_server" {
  name        = "vpn_server"
  description = "VPN port, optional SSH, all outbound traffic"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "vpn_server"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpn" {
  security_group_id = aws_security_group.vpn_server.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = module.cloud_init.port
  ip_protocol       = module.cloud_init.transport
  to_port           = module.cloud_init.port
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.vpn_server.id
  cidr_ipv4         = each.value
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.vpn_server.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
