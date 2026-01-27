variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "region" {
  type        = string
  description = "AWS region of the cluster"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to install Collibra DQ into"
  default     = "collibra-dq"
}

variable "release_name" {
  type        = string
  description = "Helm release name for Collibra DQ"
  default     = "collibra-dq"
}

variable "chart_repo" {
  type        = string
  description = "Collibra DQ Helm chart repository URL or name"
  # Note: Update this with the actual Collibra DQ Helm chart repository URL
  # This is typically provided by Collibra support or documentation
  default     = ""
}

variable "chart_version" {
  type        = string
  description = "Chart version to install; empty for latest"
  default     = ""
}

variable "chart_name" {
  type        = string
  description = "Collibra DQ Helm chart name"
  default     = "collibra-dq"
}

variable "license_key" {
  type        = string
  description = "Collibra DQ license key"
  sensitive   = true
}

variable "postgresql_host" {
  type        = string
  description = "External PostgreSQL database hostname or endpoint"
}

variable "postgresql_port" {
  type        = number
  description = "PostgreSQL database port"
  default     = 5432
}

variable "postgresql_database" {
  type        = string
  description = "PostgreSQL database name for Collibra DQ metastore"
  default     = "collibra_dq"
}

variable "postgresql_username" {
  type        = string
  description = "PostgreSQL database username"
  sensitive   = true
}

variable "postgresql_password" {
  type        = string
  description = "PostgreSQL database password"
  sensitive   = true
}

variable "image_registry_url" {
  type        = string
  description = "Container registry URL for Collibra DQ images (gcr.io for Collibra registry, or your private registry URL)"
  # Note: Collibra images are in Google Artifact Registry (gcr.io)
  # For private registry, use your registry URL after pulling and pushing images
  default     = "gcr.io"
}

variable "image_registry_username" {
  type        = string
  description = "Username for container registry (use '_json_key' for gcr.io, or your registry username for private registry)"
  default     = "_json_key"
  sensitive   = true

  validation {
    condition     = var.existing_image_pull_secret != "" || trimspace(var.image_registry_username) != ""
    error_message = "Provide image_registry_username when existing_image_pull_secret is empty."
  }
}

variable "image_registry_password" {
  type        = string
  description = "Password for private container registry (required if existing_image_pull_secret is empty)"
  default     = ""
  sensitive   = true

  validation {
    condition     = var.existing_image_pull_secret != "" || trimspace(var.image_registry_password) != ""
    error_message = "Provide image_registry_password when existing_image_pull_secret is empty."
  }
}

variable "existing_image_pull_secret" {
  type        = string
  description = "Optional: name of an existing imagePullSecret to use (if set, TF won't create one). Default Helm chart expects 'dq-pull-secret'"
  default     = ""
}

variable "image_pull_secret_version" {
  type        = string
  description = "Rollout knob when reusing an external secret; bump to force Helm upgrade (e.g., v1 -> v2)."
  default     = "v1"
}

variable "service_type" {
  type        = string
  description = "Kubernetes service type for DQ Web (LoadBalancer, NodePort, or ClusterIP)"
  default     = "LoadBalancer"
  
  validation {
    condition     = contains(["LoadBalancer", "NodePort", "ClusterIP"], var.service_type)
    error_message = "service_type must be LoadBalancer, NodePort, or ClusterIP."
  }
}

variable "create_namespace" {
  type        = bool
  description = "Create the namespace if it doesn't exist (passed to Helm)"
  default     = true
}

variable "resource_requests" {
  type = object({
    dq_web = object({
      cpu    = string
      memory = string
    })
    dq_agent = object({
      cpu    = string
      memory = string
    })
    dq_metastore = object({
      cpu    = string
      memory = string
    })
    spark = object({
      cpu    = string
      memory = string
    })
  })
  description = "Resource requests for Collibra DQ components"
  default = {
    dq_web = {
      cpu    = "1"
      memory = "2Gi"
    }
    dq_agent = {
      cpu    = "1"
      memory = "1Gi"
    }
    dq_metastore = {
      cpu    = "1"
      memory = "2Gi"
    }
    spark = {
      cpu    = "2"
      memory = "2Gi"
    }
  }
}

variable "resource_limits" {
  type = object({
    dq_web = object({
      cpu    = string
      memory = string
    })
    dq_agent = object({
      cpu    = string
      memory = string
    })
    dq_metastore = object({
      cpu    = string
      memory = string
    })
    spark = object({
      cpu    = string
      memory = string
    })
  })
  description = "Resource limits for Collibra DQ components"
  default = {
    dq_web = {
      cpu    = "1"
      memory = "2Gi"
    }
    dq_agent = {
      cpu    = "1"
      memory = "1Gi"
    }
    dq_metastore = {
      cpu    = "1"
      memory = "2Gi"
    }
    spark = {
      cpu    = "2"
      memory = "2Gi"
    }
  }
}

variable "ssl_keystore_path" {
  type        = string
  description = "Path to SSL keystore file (keystore.jks) - will be created as Kubernetes secret"
  default     = ""
}

variable "ssl_keystore_secret_name" {
  type        = string
  description = "Name for the SSL keystore Kubernetes secret. Default Helm chart expects 'dq-ssl-secret'"
  default     = "dq-ssl-secret"
}

variable "gcs_secret_path" {
  type        = string
  description = "Path to GCS service account JSON key file (if using GCS for Spark history logs). Creates secret named 'spark-gcs-secret'"
  default     = ""
}

variable "gcs_secret_name" {
  type        = string
  description = "Name for the GCS credential Kubernetes secret. Default Helm chart expects 'spark-gcs-secret'"
  default     = "spark-gcs-secret"
}

variable "spark_service_account_name" {
  type        = string
  description = "Name for the Spark service account (if not using default). Default: Collibra DQ creates service account with Edit role"
  default     = ""
}

variable "dq_version" {
  type        = string
  description = "Collibra DQ version tag (e.g., '2025.11-ABDGCSHILM-4255' or '2025.11-4254'). See Collibra DQ Builds documentation for available versions. If empty, uses Helm chart default."
  default     = ""
}

variable "spark_version" {
  type        = string
  description = "Spark version tag (e.g., '3.5.6-2025.11-ABDGCSHILM-4255' or '3.5.6-2025.11-4254'). Must match DQ version. If empty, uses Helm chart default."
  default     = ""
}

variable "additional_values" {
  type        = map(string)
  description = "Additional Helm values to pass to the chart (key-value pairs)"
  default     = {}
}
