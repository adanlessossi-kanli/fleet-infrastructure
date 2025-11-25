# Fleet Management System - AWS Infrastructure

Production-ready Terraform infrastructure for the Fleet Management System.

## 🏗️ Architecture Overview

This infrastructure creates a highly available, scalable, and secure environment for running a fleet management system on AWS.

### Components

- **VPC**: Multi-AZ networking with public, private, and database subnets
- **RDS PostgreSQL**: Managed database with automated backups
- **ECS Fargate**: Containerized API with auto-scaling
- **Application Load Balancer**: HTTPS endpoint with SSL/TLS
- **ElastiCache Redis**: Real-time data caching
- **S3 + CloudFront**: Static asset storage and CDN
- **CloudWatch**: Monitoring, logging, and alarms

### Architecture Diagram
```
Internet
    │
    ├─── CloudFront CDN ──────── S3 Bucket (Static Assets)
    │
    └─── Application Load Balancer (Public Subnets)
              │
              ├─── ECS Fargate Tasks (Private Subnets)
              │         │
              │         ├─── RDS PostgreSQL (Database Subnets)
              │         └─── ElastiCache Redis (Private Subnets)
              │
              └─── NAT Gateway ──────── Internet Gateway
```

## 📋 Prerequisites

### Required Software

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Docker](https://www.docker.com/) (for building container images)
- Git

### AWS Account Requirements

- AWS Account with appropriate permissions
- AWS Access Key ID and Secret Access Key
- Ability to create VPCs, EC2 instances, RDS databases, etc.

## 🚀 Quick Start

### 1. Clone and Setup
```bash
# Clone the repository
git clone <your-repo-url>
cd fleet-infrastructure

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

### 2. Configure AWS Credentials
```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output: json
```

### 3. Create S3 Backend
```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://fleet-management-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket fleet-management-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name fleet-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 4. Build and Push Docker Image
```bash
# Create ECR repository
aws ecr create-repository --repository-name fleet-api --region us-east-1

# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# Build your Docker image (from your application directory)
docker build -t fleet-api .

# Tag the image
docker tag fleet-api:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/fleet-api:latest

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/fleet-api:latest
```

### 5. Initialize Terraform
```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format code
terraform fmt -recursive
```

### 6. Deploy Infrastructure
```bash
# Review the execution plan
terraform plan

# Apply the infrastructure
terraform apply

# Type 'yes' when prompted
# Deployment takes approximately 15-20 minutes
```

### 7. Get Outputs
```bash
# View all outputs
terraform output

# Get specific output
terraform output api_endpoint
terraform output database_endpoint
```

## 📁 Project Structure
```
fleet-infrastructure/
├── main.tf                      # Main orchestration
├── variables.tf                 # Variable definitions
├── terraform.tfvars             # Configuration values (git-ignored)
├── terraform.tfvars.example     # Configuration template
├── .gitignore                   # Git ignore rules
├── README.md                    # This file
└── modules/
    ├── vpc/                     # VPC and networking
    ├── rds/                     # PostgreSQL database
    ├── ecs/                     # ECS cluster and services
    ├── s3/                      # S3 and CloudFront
    ├── elasticache/             # Redis cache
    └── monitoring/              # CloudWatch alarms and dashboards
```

## 🔧 Configuration

### Important Variables

Edit `terraform.tfvars` with your specific values:
```hcl
# Required
aws_region           = "us-east-1"
environment          = "production"
db_password          = "YOUR_STRONG_PASSWORD"
api_container_image  = "YOUR_ECR_IMAGE_URL"
alarm_email          = "your-email@example.com"

# Optional
ssl_certificate_arn  = "arn:aws:acm:..."  # For HTTPS
```

### Environment-Specific Configurations

**Development:**
```hcl
environment = "dev"
db_instance_class = "db.t3.micro"
ecs_desired_count = 1
```

**Staging:**
```hcl
environment = "staging"
db_instance_class = "db.t3.small"
ecs_desired_count = 2
```

**Production:**
```hcl
environment = "production"
db_instance_class = "db.t3.medium"
ecs_desired_count = 4
```

## 💰 Cost Estimation

Approximate monthly costs (us-east-1):

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| VPC & Networking | NAT Gateway x3 | $30-50 |
| RDS PostgreSQL | db.t3.medium | $80-100 |
| ECS Fargate | 2-10 tasks | $60-300 |
| Application Load Balancer | Standard | $20-25 |
| ElastiCache Redis | cache.t3.micro | $15-20 |
| S3 + CloudFront | Standard usage | $5-30 |
| CloudWatch | Logs + Alarms | $5-15 |

**Total: ~$225-540/month** (varies with traffic and usage)

## 🔒 Security Features

- ✅ All data encrypted at rest (AES-256)
- ✅ All data encrypted in transit (TLS 1.3)
- ✅ Private subnets for application layer
- ✅ Isolated database subnets (no internet access)
- ✅ Security groups with least privilege
- ✅ VPC Flow Logs enabled
- ✅ Database credentials stored securely
- ✅ Redis authentication enabled
- ✅ S3 buckets blocked from public access
- ✅ CloudFront for secure content delivery

## 📊 Monitoring

### CloudWatch Dashboard

Access your dashboard:
```bash
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=$(terraform output -raw environment)-fleet-dashboard"
```

### Alarms Configured

- ECS CPU utilization > 80%
- ECS Memory utilization > 85%
- RDS CPU utilization > 80%
- RDS Free storage < 10 GB
- RDS Connections > 80
- ALB Response time > 1 second
- ALB 5XX errors > 10

### View Logs
```bash
# ECS application logs
aws logs tail /ecs/production-fleet-api --follow --format short

# RDS logs
aws rds describe-db-log-files \
  --db-instance-identifier production-fleet-postgres
```

## 🔄 Common Operations

### Update Application
```bash
# Build new image
docker build -t fleet-api .

# Push to ECR
docker tag fleet-api:latest ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/fleet-api:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/fleet-api:latest

# Force ECS to pull new image
aws ecs update-service \
  --cluster production-fleet-cluster \
  --service production-fleet-api \
  --force-new-deployment
```

### Scale ECS Tasks
```bash
# Update terraform.tfvars
ecs_desired_count = 5

# Apply changes
terraform apply
```

### Database Backup
```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier production-fleet-postgres \
  --db-snapshot-identifier manual-backup-$(date +%Y%m%d)
```

### View Current Resources
```bash
# List all resources
terraform state list

# Show specific resource
terraform state show module.vpc.aws_vpc.main
```

## 🧪 Testing

### Health Check
```bash
API_URL=$(terraform output -raw api_endpoint)
curl http://$API_URL/health
```

### Load Testing
```bash
# Install Apache Bench
# macOS: brew install httpd
# Linux: sudo apt-get install apache2-utils

# Run load test
ab -n 1000 -c 10 http://$API_URL/health
```

## 🆘 Troubleshooting

### ECS Tasks Not Starting
```bash
# Check service events
aws ecs describe-services \
  --cluster production-fleet-cluster \
  --services production-fleet-api \
  --query 'services[0].events[:5]'

# Check task status
aws ecs list-tasks --cluster production-fleet-cluster

# View logs
aws logs tail /ecs/production-fleet-api --since 30m
```

### Database Connection Issues
```bash
# Check security group rules
aws ec2 describe-security-groups \
  --filters Name=group-name,Values=production-fleet-rds-sg

# Test connectivity from ECS task
aws ecs execute-command \
  --cluster production-fleet-cluster \
  --task <task-id> \
  --interactive \
  --command "/bin/sh"
```

## 🗑️ Cleanup

**⚠️ WARNING: This will destroy all resources and data!**
```bash
# Remove deletion protection from RDS
aws rds modify-db-instance \
  --db-instance-identifier production-fleet-postgres \
  --no-deletion-protection

# Destroy infrastructure
terraform destroy

# Confirm by typing: yes
```

## 📚 Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Summary

✅ 25 production-ready files
✅ Complete AWS infrastructure (VPC, RDS, ECS, Redis, S3, Monitoring)
✅ Auto-scaling (2-10 tasks based on CPU/memory)
✅ High availability (Multi-AZ deployment)
✅ Security (Encryption, private subnets, security groups)
✅ Monitoring (CloudWatch dashboards and alarms)
✅ Cost-optimized (~$225-540/month)
✅ Makefile with 25+ helpful commands
✅ Documentation (README + Deployment Guide)

Fleet management system infrastructure is ready to be deployed! 🎊


## 📝 License

[Your License Here]

## 👥 Contributors

[Your Team Information]

---

**Last Updated**: November 2024