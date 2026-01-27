terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = ">= 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.23, < 3.0" }
    helm       = { source = "hashicorp/helm", version = ">= 2.12, < 3.0" }
  }
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ---------- Namespace creation ----------
resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "collibra-dq"
      "app.kubernetes.io/instance" = var.release_name
    }
  }
}

# ---------- Image pull secret handling ----------
locals {
  using_existing_pullsec = trimspace(var.existing_image_pull_secret) != ""
  registry_url           = var.image_registry_url != "" ? var.image_registry_url : "registry.collibra.com" # Default registry URL

  dockerconfigjson = jsonencode({
    auths = {
      (local.registry_url) = {
        username = var.image_registry_username
        password = var.image_registry_password
      }
    }
  })

  # Changes when credentials change → used to trigger rollout
  secret_checksum = sha256(local.dockerconfigjson)
}

# Create the imagePullSecret only when NOT reusing an existing one
resource "kubernetes_secret" "image_pull" {
  count = local.using_existing_pullsec ? 0 : 1

  metadata {
    name      = "${var.release_name}-pullsecret"
    namespace = var.namespace
  }

  type = "kubernetes.io/docker-registry"

  data = {
    ".dockerconfigjson" = base64encode(local.dockerconfigjson)
  }

  # Clean rotation on cred changes
  lifecycle {
    replace_triggered_by = [terraform_data.rotate_secret.id]
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }

  depends_on = [kubernetes_namespace.this]
}

# Lightweight trigger to force replacement when secret content changes
resource "terraform_data" "rotate_secret" {
  triggers_replace = { checksum = local.secret_checksum }
}

# Resolve the secret name regardless of creation path
locals {
  image_pull_secret_name = local.using_existing_pullsec ? var.existing_image_pull_secret : try(kubernetes_secret.image_pull[0].metadata[0].name, null)
}

# ---------- PostgreSQL connection secret ----------
resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "${var.release_name}-postgresql"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    host     = base64encode(var.postgresql_host)
    port     = base64encode(tostring(var.postgresql_port))
    database = base64encode(var.postgresql_database)
    username = base64encode(var.postgresql_username)
    password = base64encode(var.postgresql_password)
  }

  depends_on = [kubernetes_namespace.this]
}

# ---------- License key secret ----------
resource "kubernetes_secret" "license" {
  metadata {
    name      = "${var.release_name}-license"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    license-key = base64encode(var.license_key)
  }

  depends_on = [kubernetes_namespace.this]
}

# ---------- Helm release ----------
resource "helm_release" "collibra_dq" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = false # We create the namespace explicitly with kubernetes_namespace resource
  repository       = var.chart_repo
  chart            = var.chart_name
  version          = var.chart_version
  atomic           = true
  wait_for_jobs    = true
  timeout          = 900
  lint             = false

  # License key
  set {
    name  = "licenseKey"
    value = var.license_key
  }

  # PostgreSQL connection
  set {
    name  = "postgresql.host"
    value = var.postgresql_host
  }

  set {
    name  = "postgresql.port"
    value = tostring(var.postgresql_port)
  }

  set {
    name  = "postgresql.database"
    value = var.postgresql_database
  }

  set {
    name  = "postgresql.username"
    value = var.postgresql_username
  }

  set {
    name  = "postgresql.password"
    value = var.postgresql_password
  }

  # Service type for DQ Web
  set {
    name  = "dqWeb.service.type"
    value = var.service_type
  }

  # Resource requests
  set {
    name  = "dqWeb.resources.requests.cpu"
    value = var.resource_requests.dq_web.cpu
  }

  set {
    name  = "dqWeb.resources.requests.memory"
    value = var.resource_requests.dq_web.memory
  }

  set {
    name  = "dqAgent.resources.requests.cpu"
    value = var.resource_requests.dq_agent.cpu
  }

  set {
    name  = "dqAgent.resources.requests.memory"
    value = var.resource_requests.dq_agent.memory
  }

  set {
    name  = "dqMetastore.resources.requests.cpu"
    value = var.resource_requests.dq_metastore.cpu
  }

  set {
    name  = "dqMetastore.resources.requests.memory"
    value = var.resource_requests.dq_metastore.memory
  }

  set {
    name  = "spark.resources.requests.cpu"
    value = var.resource_requests.spark.cpu
  }

  set {
    name  = "spark.resources.requests.memory"
    value = var.resource_requests.spark.memory
  }

  # Resource limits
  set {
    name  = "dqWeb.resources.limits.cpu"
    value = var.resource_limits.dq_web.cpu
  }

  set {
    name  = "dqWeb.resources.limits.memory"
    value = var.resource_limits.dq_web.memory
  }

  set {
    name  = "dqAgent.resources.limits.cpu"
    value = var.resource_limits.dq_agent.cpu
  }

  set {
    name  = "dqAgent.resources.limits.memory"
    value = var.resource_limits.dq_agent.memory
  }

  set {
    name  = "dqMetastore.resources.limits.cpu"
    value = var.resource_limits.dq_metastore.cpu
  }

  set {
    name  = "dqMetastore.resources.limits.memory"
    value = var.resource_limits.dq_metastore.memory
  }

  set {
    name  = "spark.resources.limits.cpu"
    value = var.resource_limits.spark.cpu
  }

  set {
    name  = "spark.resources.limits.memory"
    value = var.resource_limits.spark.memory
  }

  # Image pull secret
  set {
    name  = "podAnnotations.secret-checksum"
    value = local.secret_checksum
  }

  set {
    name  = "podAnnotations.image-pull-secret-version"
    value = var.image_pull_secret_version
  }

  # Pass imagePullSecrets (existing or newly created)
  dynamic "set" {
    for_each = local.image_pull_secret_name != null ? [1] : []
    content {
      name  = "imagePullSecrets[0].name"
      value = local.image_pull_secret_name
    }
  }

  # Additional values from var.additional_values
  dynamic "set" {
    for_each = var.additional_values
    content {
      name  = set.key
      value = set.value
    }
  }

  # Ensure namespace and secrets are created first when TF manages them
  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.image_pull,
    kubernetes_secret.postgresql,
    kubernetes_secret.license
  ]
}
