variable "server_ip" {
  description = "Public IP the client profiles point to"
  type        = string
}

variable "protocol" {
  description = "VPN protocol: wireguard or openvpn"
  type        = string

  validation {
    condition     = contains(["wireguard", "openvpn"], var.protocol)
    error_message = "protocol must be wireguard or openvpn."
  }
}

variable "wireguard_port" {
  description = "WireGuard UDP port"
  type        = number
  default     = 51820
}

variable "wireguard_peers" {
  description = "WireGuard client names, one profile and QR code per name"
  type        = list(string)
  default     = ["phone", "laptop"]

  validation {
    condition     = length(var.wireguard_peers) > 0 && alltrue([for p in var.wireguard_peers : can(regex("^[a-z0-9-]+$", p))])
    error_message = "At least one peer is required; names may contain only a-z, 0-9 and dashes."
  }
}

variable "profile_upload" {
  description = "Presigned S3 POST (url and form fields, __FILENAME__ stands for S3's $${filename}); null skips the upload"
  type = object({
    url    = string
    fields = map(string)
  })
  default   = null
  sensitive = true
}

variable "ssh_public_key" {
  description = "Public key for the vpn-admin user; null disables the user"
  type        = string
  default     = null
}

locals {
  repo_root = "${path.module}/../../.."

  files = {
    "/opt/vpn/bootscript.sh"       = { source = "scripts/bootscript.sh", permissions = "0700" }
    "/opt/vpn/nat.rules"           = { source = "configs/nat.rules", permissions = "0644" }
    "/opt/vpn/openvpn/server.conf" = { source = "configs/openvpn/server.conf", permissions = "0644" }
    "/opt/vpn/openvpn/client.conf" = { source = "configs/openvpn/client.conf", permissions = "0644" }
    "/opt/vpn/wireguard/wg0.conf"  = { source = "configs/wireguard/wg0.conf", permissions = "0644" }
    "/opt/vpn/wireguard/client.conf" = {
      source      = "configs/wireguard/client.conf"
      permissions = "0644"
    }
  }
  file_contents = { for path, f in local.files : path => file("${local.repo_root}/${f.source}") }

  listener = {
    wireguard = { port = var.wireguard_port, transport = "udp" }
    openvpn   = { port = 443, transport = "tcp" }
  }[var.protocol]

  env = <<-EOT
    SERVER_IP='${var.server_ip}'
    PROTOCOL='${var.protocol}'
    VPN_PORT='${local.listener.port}'
    VPN_TRANSPORT='${local.listener.transport}'
    WIREGUARD_PEERS='${join(" ", var.wireguard_peers)}'
  EOT

  # curl config for S3 POST; the file field is added by bootscript.sh and must go last
  upload_curlrc = var.profile_upload == null ? null : join("\n", concat(
    ["url = \"${var.profile_upload.url}\""],
    [for k, v in var.profile_upload.fields : "form-string = \"${k}=${replace(v, "__FILENAME__", "$${filename}")}\""],
    [""],
  ))

  generated_files = concat(
    [{ path = "/opt/vpn/env", content = local.env }],
    local.upload_curlrc == null ? [] : [{ path = "/opt/vpn/upload.curlrc", content = local.upload_curlrc }],
  )

  admin_users = var.ssh_public_key == null ? [] : [{
    name                = "vpn-admin"
    groups              = ["sudo"]
    shell               = "/bin/bash"
    sudo                = "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys = [var.ssh_public_key]
  }]

  cloud_config = {
    users = concat(["default"], local.admin_users)
    write_files = concat(
      [for path, f in local.files : {
        path        = path
        permissions = f.permissions
        encoding    = "b64"
        content     = base64encode(local.file_contents[path])
      }],
      [for f in local.generated_files : {
        path        = f.path
        permissions = "0600"
        encoding    = "b64"
        content     = base64encode(f.content)
      }],
    )
    runcmd = [["/opt/vpn/bootscript.sh"]]
  }
}

output "user_data" {
  description = "cloud-config for the VPN server"
  value       = "#cloud-config\n${yamlencode(local.cloud_config)}"
  sensitive   = true
}

output "config_hash" {
  description = "Changes whenever the server has to be rebuilt; the one-off upload credentials are excluded"
  value = sha256(jsonencode({
    files          = local.file_contents
    env            = local.env
    ssh_public_key = var.ssh_public_key
  }))
}

output "port" {
  description = "Port the VPN server listens on"
  value       = local.listener.port
}

output "transport" {
  description = "Transport protocol of the VPN port: udp or tcp"
  value       = local.listener.transport
}
