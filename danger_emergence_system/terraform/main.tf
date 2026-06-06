# terraform/main.tf
terraform {
  required_version = ">= 1.5"
  backend "gcs" {
    bucket = "danger-emergence-terraform-state"
    prefix = "prod"
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "danger-emergence-prod"
  location = var.gcp_region
  
  remove_default_node_pool = true
  initial_node_count       = 1
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
  
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
  }
}

# Node pool for backend services
resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = 3
  
  node_config {
    machine_type = "n2-standard-4"
    disk_size_gb = 100
    disk_type    = "pd-ssd"
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    labels = {
      environment = "production"
      team        = "backend"
    }
  }
  
  autoscaling {
    min_node_count = 3
    max_node_count = 10
  }
}

# Node pool for ML workloads (GPU)
resource "google_container_node_pool" "gpu_nodes" {
  name       = "gpu-node-pool"
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = 1
  
  node_config {
    machine_type = "n1-standard-8"
    disk_size_gb = 200
    disk_type    = "pd-ssd"
    
    guest_accelerator {
      type  = "nvidia-tesla-t4"
      count = 1
    }
    
    metadata = {
      install-nvidia-driver = "true"
    }
  }
  
  autoscaling {
    min_node_count = 0
    max_node_count = 3
  }
}

# PostgreSQL Cloud SQL
resource "google_sql_database_instance" "postgres" {
  name             = "danger-emergence-db"
  database_version = "POSTGRES_15"
  region          = var.gcp_region
  
  settings {
    tier              = "db-custom-4-16384"
    disk_size         = 100
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    availability_type = "REGIONAL"
    
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }
    
    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.vpc.id
      
      authorized_networks {
        name  = "k8s-nodes"
        value = google_container_cluster.primary.private_cluster_config[0].master_ipv4_cidr_block
      }
    }
  }
}

# Redis Memorystore
resource "google_redis_instance" "cache" {
  name           = "danger-emergence-cache"
  tier           = "STANDARD_HA"
  memory_size_gb = 5
  region         = var.gcp_region
  
  redis_version     = "REDIS_7_0"
  display_name      = "Danger Emergence Cache"
  reserved_ip_range = "10.0.0.0/29"
  
  persistence_config {
    persistence_mode = "RDB"
    rdb_snapshot_period = "TWELVE_HOURS"
  }
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "danger-emergence-vpc"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "danger-emergence-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  
  private_ip_google_access = true
}

# Cloud Armor for DDoS protection
resource "google_compute_security_policy" "armor" {
  name = "danger-emergence-armor"
  
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["34.0.0.0/8"]  # Block Google Cloud IPs (example)
      }
    }
    description = "Block suspicious IP ranges"
  }
  
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
}

# Outputs
output "cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "db_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "redis_ip" {
  value = google_redis_instance.cache.host
}
