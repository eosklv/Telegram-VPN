# Resources created by hand before this stack existed; the blocks are no-ops once imported

import {
  to = aws_s3_bucket.state
  id = var.bucket_name
}

import {
  to = aws_s3_bucket_versioning.state
  id = var.bucket_name
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.state
  id = var.bucket_name
}

import {
  to = aws_s3_bucket_public_access_block.state
  id = var.bucket_name
}

import {
  to = aws_s3_bucket_ownership_controls.state
  id = var.bucket_name
}

import {
  to = aws_iam_openid_connect_provider.github
  id = local.github_oidc_arn
}

import {
  to = aws_iam_role.github
  id = "GithubAccess"
}
