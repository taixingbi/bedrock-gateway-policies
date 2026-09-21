# This repo's own CI identity (policy publish) -- Terraform-ownership
# migration from platform-foundation (2026-09-21), step 5 of 6 (the
# simplest: 1 role, following AuthZ, Control Plane, Edge Gateway, and
# Runtime Gateway). This IAM role already existed, created and managed
# by platform-foundation/environments/global's module
# "github_oidc_policies" call. Moved here via `terraform import`
# (never delete/recreate) so this repo owns its own CI permissions
# going forward. ARN is unchanged; this repo's GitHub Environment
# variable does not need to change.
#
# Phase 1 (interim, current) has nothing for this role to actually do --
# delivery is a manual copy into the app repo, not an automated
# publish. Scoped ahead of time to phase 2's planned DynamoDB table
# name so the trust relationship/role identity already exists; inert
# until that table does.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_iam_policy_document" "policy_publish" {
  statement {
    sid       = "PublishToPolicyTable"
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/gateway-policies"]
  }
}

module "github_oidc" {
  source = "git::https://github.com/taixingbi/platform-foundation.git//modules/github_oidc?ref=main"

  # The account-wide OIDC provider is owned by platform-foundation
  # (module.github_oidc_foundation) -- every other repo, this one
  # included, only ever references it via data source.
  create_oidc_provider = false
  github_org           = var.github_org
  github_repo          = "platform-policy-definitions"

  roles = {
    publish = {
      role_name   = "gha-policy-publish"
      policy_json = data.aws_iam_policy_document.policy_publish.json
    }
  }
}
