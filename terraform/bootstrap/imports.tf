# Opt-in adoption of a bucket and a role created by hand before this stack (import_existing = true).
# Once imported, the blocks are no-ops and the variable can be turned off again.

locals {
  bucket_import = var.import_existing ? toset([var.bucket_name]) : toset([])
  role_import   = var.import_existing ? toset([var.github_role_name]) : toset([])
}

import {
  for_each = local.bucket_import
  to       = aws_s3_bucket.state
  id       = each.value
}

import {
  for_each = local.bucket_import
  to       = aws_s3_bucket_versioning.state
  id       = each.value
}

import {
  for_each = local.bucket_import
  to       = aws_s3_bucket_server_side_encryption_configuration.state
  id       = each.value
}

import {
  for_each = local.bucket_import
  to       = aws_s3_bucket_public_access_block.state
  id       = each.value
}

import {
  for_each = local.bucket_import
  to       = aws_s3_bucket_ownership_controls.state
  id       = each.value
}

import {
  for_each = local.role_import
  to       = aws_iam_role.github
  id       = each.value
}
