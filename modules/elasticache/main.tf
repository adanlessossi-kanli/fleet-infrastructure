# modules/elasticache/main.tf - Redis Cache Configuration

# Subnet group for ElastiCache
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.environment}-fleet-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.environment}-fleet-redis-subnet-group"
  }
}

# Security Group for Redis
resource "aws_security_group" "redis" {
  name        = "${var.environment}-fleet-redis-sg"
  description = "Security group for Redis cache"
  vpc_id      = var.vpc_id

  ingress {
    description = "Redis from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-fleet-redis-sg"
  }
}

# Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.environment}-fleet-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = {
    Name = "${var.environment}-fleet-redis-params"
  }
}

# Redis Cluster
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.environment}-fleet-redis"
  description          = "Redis cache for Fleet Management System"
  
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes
  port                 = 6379
  
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
  
  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false
  multi_az_enabled          = var.num_cache_nodes > 1 ? true : false
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                = random_password.redis_auth.result
  
  snapshot_retention_limit = 5
  snapshot_window         = "03:00-05:00"
  maintenance_window      = "sun:05:00-sun:07:00"
  
  auto_minor_version_upgrade = true
  
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = {
    Name = "${var.environment}-fleet-redis"
  }
}

# Random password for Redis
resource "random_password" "redis_auth" {
  length  = 32
  special = true
}

# Store auth token in Secrets Manager
resource "aws_secretsmanager_secret" "redis_auth" {
  name = "${var.environment}/fleet/redis-auth"
  
  tags = {
    Name = "${var.environment}-fleet-redis-auth"
  }
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = random_password.redis_auth.result
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "/aws/elasticache/${var.environment}-fleet-redis/slow-log"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "redis_engine" {
  name              = "/aws/elasticache/${var.environment}-fleet-redis/engine-log"
  retention_in_days = 7
}