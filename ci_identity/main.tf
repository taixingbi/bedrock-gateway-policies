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

# This repo's own Terraform plan/apply-dev roles for ci_identity itself
# -- brand new, unlike every other migrated repo (this one never had
# ANY Terraform plan/apply role before; "publish" is a pure deploy-
# style role, no Terraform of its own to run). Same naming convention
# as every sibling repo's own infra plan/apply-dev roles.
data "aws_iam_policy_document" "policy_infra_plan" {
  statement {
    sid       = "IamReadOnly"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid       = "StsReadOnly"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    sid       = "TerraformStateS3"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::*tfstate*", "arn:aws:s3:::*tfstate*/*"]
  }
}

data "aws_iam_policy_document" "policy_infra_apply" {
  statement {
    sid = "ManagePolicyRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies", "iam:TagRole", "iam:UntagRole", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/gha-policy-*"]
  }
  statement {
    sid       = "OidcProviderReadOnly"
    actions   = ["iam:ListOpenIDConnectProviders", "iam:GetOpenIDConnectProvider"]
    resources = ["*"]
  }
  statement {
    sid       = "TerraformStateS3"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::*tfstate*", "arn:aws:s3:::*tfstate*/*"]
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
    plan = {
      role_name   = "gha-policy-infra-plan"
      policy_json = data.aws_iam_policy_document.policy_infra_plan.json
    }
    apply-dev = {
      role_name   = "gha-policy-infra-apply-dev"
      policy_json = data.aws_iam_policy_document.policy_infra_apply.json
    }
  }
}
