# modules/ecs/variables.tf

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "service_name" {
  description = "ECS service name"
  type        = string
}

variable "container_image" {
  description = "Docker container image"
  type        = string
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "cpu" {
  description = "CPU units for task"
  type        = string
}

variable "memory" {
  description = "Memory for task in MB"
  type        = string
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
}

variable "min_capacity" {
  description = "Minimum capacity for auto-scaling"
  type        = number
}

variable "max_capacity" {
  description = "Maximum capacity for auto-scaling"
  type        = number
}

variable "db_host" {
  description = "Database host endpoint"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "certificate_arn" {
  description = "SSL certificate ARN for HTTPS"
  type        = string
  default     = ""
}