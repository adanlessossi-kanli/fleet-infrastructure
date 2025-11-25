# main.tf - Fleet Management System Infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "fleet-management-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "fleet-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "FleetManagement"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}

# RDS PostgreSQL Database
module "database" {
  source = "./modules/rds"

  environment           = var.environment
  vpc_id               = module.vpc.vpc_id
  database_subnet_ids  = module.vpc.database_subnet_ids
  
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  db_instance_class    = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  
  backup_retention_period = 7
  multi_az               = var.environment == "production" ? true : false
}

# ECS Cluster for API
module "ecs" {
  source = "./modules/ecs"

  environment          = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  
  cluster_name        = "${var.environment}-fleet-cluster"
  service_name        = "${var.environment}-fleet-api"
  
  container_image     = var.api_container_image
  container_port      = 8000
  cpu                = var.ecs_task_cpu
  memory             = var.ecs_task_memory
  
  desired_count      = var.ecs_desired_count
  min_capacity       = var.ecs_min_capacity
  max_capacity       = var.ecs_max_capacity
  
  db_host            = module.database.db_endpoint
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  
  certificate_arn    = var.ssl_certificate_arn
}

# S3 Bucket for Static Assets and Uploads
module "storage" {
  source = "./modules/s3"

  environment     = var.environment
  bucket_name     = "${var.environment}-fleet-storage"
  enable_versioning = true
}

# ElastiCache Redis for Real-time Features
module "cache" {
  source = "./modules/elasticache"

  environment         = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  
  node_type          = var.redis_node_type
  num_cache_nodes    = var.redis_num_nodes
}

# CloudWatch Monitoring and Alarms
module "monitoring" {
  source = "./modules/monitoring"

  environment           = var.environment
  ecs_cluster_name     = module.ecs.cluster_name
  ecs_service_name     = module.ecs.service_name
  db_instance_id       = module.database.db_instance_id
  alb_arn_suffix       = module.ecs.alb_arn_suffix
  
  alarm_email          = var.alarm_email
}

# Outputs
output "api_endpoint" {
  description = "Load Balancer DNS name for API"
  value       = module.ecs.alb_dns_name
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis cache endpoint"
  value       = module.cache.redis_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket for storage"
  value       = module.storage.bucket_name
}

output "cloudfront_domain" {
  description = "CloudFront CDN domain"
  value       = module.storage.cloudfront_domain
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}