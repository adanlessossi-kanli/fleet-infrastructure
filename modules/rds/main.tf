# modules/rds/main.tf - RDS PostgreSQL Configuration

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-fleet-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = {
    Name = "${var.environment}-fleet-db-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.environment}-fleet-rds-sg"
  description = "Security group for RDS database"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
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
    Name = "${var.environment}-fleet-rds-sg"
  }
}

# RDS Parameter Group
resource "aws_db_parameter_group" "main" {
  name   = "${var.environment}-fleet-postgres-params"
  family = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = {
    Name = "${var.environment}-fleet-postgres-params"
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-fleet-postgres"
  engine         = "postgres"
  engine_version = "15.4"

  instance_class    = var.db_instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az               = var.multi_az
  publicly_accessible    = false
  backup_retention_period = var.backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  deletion_protection = var.environment == "production" ? true : false
  skip_final_snapshot = var.environment == "production" ? false : true
  final_snapshot_identifier = var.environment == "production" ? "${var.environment}-fleet-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${var.environment}-fleet-postgres"
  }
}