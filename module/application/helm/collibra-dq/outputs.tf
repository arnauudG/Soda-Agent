output "namespace" {
  description = "Namespace where Collibra DQ is deployed"
  value       = helm_release.collibra_dq.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.collibra_dq.name
}

output "image_pull_secret_name" {
  description = "Name of the imagePullSecret used by Collibra DQ (created or existing)"
  value       = local.image_pull_secret_name
}

output "postgresql_secret_name" {
  description = "Name of the PostgreSQL connection secret"
  value       = kubernetes_secret.postgresql.metadata[0].name
}

output "license_secret_name" {
  description = "Name of the license key secret"
  value       = kubernetes_secret.license.metadata[0].name
}

output "status" {
  description = "Helm release status"
  value       = helm_release.collibra_dq.status
}
