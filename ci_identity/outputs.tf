output "role_arn" {
  description = "Set as AWS_POLICY_PUBLISH_ROLE_ARN in this repo's own GitHub Environment variables -- unchanged from before this migration."
  value       = module.github_oidc.role_arns["publish"]
}
