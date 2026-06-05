# terraform/variables.tf
variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "node_count" {
  description = "Initial node count for primary node pool"
  type        = number
  default     = 3
}

variable "gpu_node_count" {
  description = "Initial node count for GPU node pool"
  type        = number
  default     = 1
}

variable "db_tier" {
  description = "Cloud SQL tier"
  type        = string
  default     = "db-custom-4-16384"
}

variable "redis_memory_gb" {
  description = "Redis instance memory in GB"
  type        = number
  default     = 5
}
