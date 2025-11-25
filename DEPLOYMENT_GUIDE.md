# Fleet Management System - Deployment Guide

Complete step-by-step deployment instructions.

## 📋 Pre-Deployment Checklist

Before starting, ensure you have:

- [ ] AWS Account with admin access
- [ ] AWS CLI installed and configured
- [ ] Terraform installed (version >= 1.0)
- [ ] Docker installed
- [ ] Git installed
- [ ] Your application code ready
- [ ] A strong database password prepared
- [ ] Email address for alerts

## 🎯 Deployment Steps

### Step 1: Prepare AWS Account

#### 1.1 Configure AWS CLI
```bash
aws configure

# You'll be prompted for:
# AWS Access Key ID: [Enter your access key]
# AWS Secret Access Key: [Enter your secret key]
# Default region name: us-east-1
# Default output format: json
```

#### 1.2 Verify AWS Access
```bash
# Verify credentials work
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-username"
# }
```

### Step 2: Set Up Terraform Backend
```bash
# Create S3 bucket for state
aws s3 mb s3://fleet-management-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket fleet-management-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket fleet-management-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name fleet-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Wait for table to be active
aws dynamodb wait table-exists --table-name fleet-terraform-locks
echo "✅ Backend storage ready!"
```

### Step 3: Prepare Your Application

#### 3.1 Create Dockerfile (if not exists)
```dockerfile
# Example Node.js Dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD node healthcheck.js || exit 1

# Start application
CMD ["node", "server.js"]
```

#### 3.2 Create Health Check Endpoint

Ensure your application has a `/health` endpoint that returns 200 OK:
```javascript
// Example Express.js health endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});
```

### Step 4: Build and Push Docker Image
```bash
# Get your AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

# Create ECR repository
aws ecr create-repository \
  --repository-name fleet-api \
  --region $AWS_REGION

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Navigate to your application directory
cd /path/to/your/application

# Build Docker image
docker build -t fleet-api:latest .

# Tag for ECR
docker tag fleet-api:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fleet-api:latest

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fleet-api:latest

echo "✅ Docker image pushed successfully!"
echo "Image URL: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fleet-api:latest"
```

### Step 5: Configure Terraform

#### 5.1 Clone Infrastructure Repository
```bash
cd ~
git clone <your-infrastructure-repo>
cd fleet-infrastructure
```

#### 5.2 Create Configuration File
```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
nano terraform.tfvars
```

#### 5.3 Update Required Values

Edit `terraform.tfvars` and update these critical values:
```hcl
# REQUIRED: Update these values
api_container_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/fleet-api:latest"  # Your ECR URL
db_password         = "YourVeryStrongPassword123!"  # Strong password (16+ chars)
alarm_email         = "your-email@company.com"      # Your email for alerts

# OPTIONAL: SSL Certificate for HTTPS
ssl_certificate_arn = ""  # Leave empty for HTTP, or add ACM certificate ARN
```

### Step 6: Request SSL Certificate (Optional but Recommended)
```bash
# Request certificate for your domain
aws acm request-certificate \
  --domain-name api.yourdomain.com \
  --validation-method DNS \
  --region us-east-1

# Get certificate ARN
aws acm list-certificates --region us-east-1

# Add DNS validation records to your domain
# (Follow instructions in AWS Console or CLI output)

# Wait for validation (can take 5-30 minutes)
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:... \
  --query 'Certificate.Status' \
  --output text

# Once validated, add ARN to terraform.tfvars:
# ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."
```

### Step 7: Initialize Terraform
```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Expected output:
# Terraform has been successfully initialized!

# Validate configuration
terraform validate

# Expected output:
# Success! The configuration is valid.

# Format code
terraform fmt -recursive
```

### Step 8: Review Deployment Plan
```bash
# Generate execution plan
terraform plan -out=tfplan

# Review carefully:
# - ~75-80 resources will be created
# - Check resource names match your environment
# - Verify regions and availability zones
# - Confirm database settings
```

**Key things to verify in the plan:**
- VPC CIDR blocks don't conflict with existing networks
- Database instance class matches your needs
- ECS task sizing is appropriate
- Region is correct (us-east-1)

### Step 9: Deploy Infrastructure
```bash
# Apply the plan
terraform apply tfplan

# Or apply directly (will show plan first):
terraform apply

# Type 'yes' when prompted

# ⏱️ Deployment takes approximately 15-20 minutes
# ☕ Grab a coffee!
```

**What's being created:**
1. ✅ VPC and networking (2 min)
2. ✅ NAT Gateways (3 min)
3. ✅ RDS Database (10-12 min)
4. ✅ ElastiCache Redis (5 min)
5. ✅ ECS Cluster and Services (3 min)
6. ✅ Load Balancer (2 min)
7. ✅ S3 and CloudFront (2 min)
8. ✅ Monitoring and Alarms (1 min)

### Step 10: Verify Deployment

#### 10.1 Get Outputs
```bash
# View all outputs
terraform output

# Save important values
export API_ENDPOINT=$(terraform output -raw api_endpoint)
export DB_ENDPOINT=$(terraform output -raw database_endpoint)

echo "API Endpoint: $API_ENDPOINT"
```

#### 10.2 Test API Health
```bash
# Test HTTP health endpoint
curl http://$API_ENDPOINT/health

# Expected response:
# {"status":"healthy"}

# If using HTTPS:
curl https://api.yourdomain.com/health
```

#### 10.3 Confirm Email Subscription

Check your email for CloudWatch alarm subscription:
1. Open email from AWS Notifications
2. Click "Confirm subscription"
3. Verify confirmation page appears

#### 10.4 Check ECS Service
```bash
# Check ECS service status
aws ecs describe-services \
  --cluster production-fleet-cluster \
  --services production-fleet-api \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'

# Expected output:
# {
#     "status": "ACTIVE",
#     "running": 2,
#     "desired": 2
# }
```

### Step 11: Run Database Migrations
```bash
# Get running task ID
TASK_ID=$(aws ecs list-tasks \
  --cluster production-fleet-cluster \
  --service-name production-fleet-api \
  --query 'taskArns[0]' \
  --output text | cut -d'/' -f3)

# Connect to task
aws ecs execute-command \
  --cluster production-fleet-cluster \
  --task $TASK_ID \
  --container api \
  --interactive \
  --command "/bin/sh"

# Inside container, run migrations:
# For Node.js with Sequelize:
npx sequelize-cli db:migrate

# For Python with Django:
python manage.py migrate

# Exit container
exit
```

### Step 12: Configure DNS (If Using Custom Domain)
```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw api_endpoint)

echo "Create a CNAME record in your DNS:"
echo "  Name: api.yourdomain.com"
echo "  Type: CNAME"
echo "  Value: $ALB_DNS"
```

**In your DNS provider (Route53, Cloudflare, etc.):**
- Create CNAME record: `api.yourdomain.com` → `production-fleet-alb-123456.us-east-1.elb.amazonaws.com`
- Wait 5-10 minutes for DNS propagation
- Test: `curl https://api.yourdomain.com/health`

### Step 13: Verify Monitoring

#### 13.1 Check CloudWatch Dashboard
```bash
# Get dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=production-fleet-dashboard"
```

#### 13.2 Verify Alarms
```bash
# List all alarms
aws cloudwatch describe-alarms \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table

# All alarms should show "OK" status
```

#### 13.3 Check Logs
```bash
# View recent API logs
aws logs tail /ecs/production-fleet-api --follow --format short

# Press Ctrl+C to stop
```

## ✅ Post-Deployment Tasks

### Create Admin User
```bash
# Connect to ECS task
TASK_ID=$(aws ecs list-tasks --cluster production-fleet-cluster \
  --service-name production-fleet-api --query 'taskArns[0]' --output text | cut -d'/' -f3)

aws ecs execute-command \
  --cluster production-fleet-cluster \
  --task $TASK_ID \
  --container api \
  --interactive \
  --command "/bin/sh"

# Create admin user (example)
npm run create-admin
# or
python manage.py createsuperuser
```

### Test Key Endpoints
```bash
API_URL=$(terraform output -raw api_endpoint)

# Health check
curl $API_URL/health

# API documentation
curl $API_URL/docs

# Test authentication
curl -X POST $API_URL/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}'
```

### Set Up Backups
```bash
# Create initial manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier production-fleet-postgres \
  --db-snapshot-identifier initial-snapshot-$(date +%Y%m%d)

# Verify snapshot
aws rds describe-db-snapshots \
  --db-instance-identifier production-fleet-postgres \
  --query 'DBSnapshots[0].Status'
```

### Document Important Information

Create a secure document with:
- ✅ API endpoint URL
- ✅ Database endpoint (keep secure!)
- ✅ Redis endpoint
- ✅ S3 bucket name
- ✅ CloudFront domain
- ✅ AWS Account ID
- ✅ ECR repository URL
- ✅ CloudWatch dashboard URL

## 🔍 Verification Checklist

- [ ] API health endpoint returns 200 OK
- [ ] ECS service shows desired count running
- [ ] Database is accessible from ECS tasks
- [ ] Redis cache is accessible
- [ ] CloudWatch alarms are in OK state
- [ ] Email alarm subscription is confirmed
- [ ] Logs are flowing to CloudWatch
- [ ] DNS resolves to load balancer (if configured)
- [ ] SSL certificate is valid (if configured)
- [ ] Database migrations completed successfully

## 🎉 Deployment Complete!

Your Fleet Management System is now running on AWS!

### Next Steps:

1. **Set up CI/CD** for automated deployments
2. **Configure monitoring alerts** for your team
3. **Document API endpoints** for your developers
4. **Set up regular backup testing**
5. **Plan disaster recovery procedures**

### Support

- AWS Console: https://console.aws.amazon.com
- Terraform Docs: https://www.terraform.io/docs
- Your infrastructure repo: [Add link]

---

**🎊 Congratulations on your successful deployment!**