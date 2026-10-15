terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.239"
    }
  }

  required_version = ">= 1.10.0"

  # State lives next to the AWS one; bucket and region are passed with -backend-config
  backend "s3" {
    key          = "terraform/yandex.tfstate"
    use_lockfile = true
  }
}

# cloud_id, folder_id and token come from YC_CLOUD_ID, YC_FOLDER_ID and YC_TOKEN
provider "yandex" {
  zone = var.zone
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

resource "yandex_vpc_network" "vpn" {
  name = "vpn"
}

resource "yandex_vpc_subnet" "vpn" {
  name           = "vpn-${var.zone}"
  zone           = var.zone
  network_id     = yandex_vpc_network.vpn.id
  v4_cidr_blocks = ["10.128.0.0/24"]
}

resource "yandex_vpc_address" "vpn_server" {
  name = "vpn-server"

  external_ipv4_address {
    zone_id = var.zone
  }
}

resource "yandex_vpc_security_group" "vpn_server" {
  name       = "vpn-server"
  network_id = yandex_vpc_network.vpn.id

  ingress {
    description    = "VPN"
    protocol       = upper(module.cloud_init.transport)
    port           = module.cloud_init.port
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      description    = "SSH"
      protocol       = "TCP"
      port           = 22
      v4_cidr_blocks = var.ssh_allowed_cidrs
    }
  }

  egress {
    description    = "All outbound traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

module "cloud_init" {
  source = "../modules/cloud-init"

  server_ip       = yandex_vpc_address.vpn_server.external_ipv4_address[0].address
  protocol        = var.protocol
  wireguard_peers = var.wireguard_peers
  profile_upload  = var.profile_upload
  ssh_public_key  = var.ssh_public_key
}

resource "terraform_data" "server_config" {
  input = module.cloud_init.config_hash
}

resource "yandex_compute_instance" "vpn_server" {
  name        = "vpn-server"
  hostname    = "vpn-server"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.vpn.id
    nat                = true
    nat_ip_address     = yandex_vpc_address.vpn_server.external_ipv4_address[0].address
    security_group_ids = [yandex_vpc_security_group.vpn_server.id]
  }

  metadata = {
    user-data = module.cloud_init.user_data
  }

  lifecycle {
    # Same as in AWS: the upload URL and the image change between runs,
    # the server is rebuilt only when its configuration changes.
    ignore_changes       = [boot_disk, metadata]
    replace_triggered_by = [terraform_data.server_config]
  }
}
