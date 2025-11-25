# modules/monitoring/variables.tf

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance ID"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix"
  type        = string
}

variable "alarm_email" {
  description = "Email for alarm notifications"
  type        = string
}