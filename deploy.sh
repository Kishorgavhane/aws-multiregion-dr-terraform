#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# AWS Multi-Region DR — Full Deploy Script
# Usage: ./deploy.sh
# ─────────────────────────────────────────────────────────────────
set -e

echo "======================================================"
echo "  AWS Multi-Region DR — Deployment Script"
echo "======================================================"

# ── Step 1: Deploy DR S3 bucket first (needed before primary CRR)
echo ""
echo "[1/5] Deploying DR S3 bucket (ap-southeast-1)..."
cd dr/
terraform init -upgrade
cp terraform.tfvars.example terraform.tfvars 2>/dev/null || true
terraform apply -target=aws_s3_bucket.dr_assets \
                -target=aws_s3_bucket_versioning.dr \
                -auto-approve

DR_BUCKET_ARN=$(terraform output -raw dr_bucket_arn)
echo "DR Bucket ARN: $DR_BUCKET_ARN"

# ── Step 2: Deploy Primary region
echo ""
echo "[2/5] Deploying Primary region (ap-south-1)..."
cd ../primary/
terraform init -upgrade
terraform apply -var="dr_bucket_arn=$DR_BUCKET_ARN" -auto-approve

PRIMARY_ALB_DNS=$(terraform output -raw alb_dns_name)
PRIMARY_ALB_ZONE=$(terraform output -raw alb_zone_id)
PRIMARY_ALB_ARN_SUFFIX=$(terraform output -raw alb_arn_suffix)
PRIMARY_TG_ARN_SUFFIX=$(terraform output -raw target_group_arn_suffix)
PRIMARY_RDS_ARN=$(terraform output -raw rds_arn)

echo "Primary ALB: $PRIMARY_ALB_DNS"
echo "Primary RDS ARN: $PRIMARY_RDS_ARN"

# ── Step 3: Deploy full DR region (RDS replica takes ~20 min)
echo ""
echo "[3/5] Deploying full DR region (ap-southeast-1)..."
echo "NOTE: RDS cross-region replica creation takes 15-30 minutes. Please wait..."
cd ../dr/
terraform apply -var="primary_rds_arn=$PRIMARY_RDS_ARN" -auto-approve

DR_ALB_DNS=$(terraform output -raw dr_alb_dns_name)
DR_ALB_ZONE=$(terraform output -raw dr_alb_zone_id)
DR_ASG_NAME=$(terraform output -raw dr_asg_name)
DR_REPLICA_ID=$(terraform output -raw dr_replica_identifier)

echo "DR ALB: $DR_ALB_DNS"

# ── Step 4: Package Lambda
echo ""
echo "[4/5] Packaging Lambda function..."
cd ../lambda/
zip -r failover.zip failover.py
echo "Lambda packaged: lambda/failover.zip"

# ── Step 5: Deploy shared resources (Route53, Lambda, CloudWatch, SNS)
echo ""
echo "[5/5] Deploying shared resources (Route 53, Lambda, CloudWatch, SNS)..."
echo "IMPORTANT: Edit shared/terraform.tfvars with your domain and email first!"
echo ""
echo "Values to fill in shared/terraform.tfvars:"
echo "  primary_alb_dns        = \"$PRIMARY_ALB_DNS\""
echo "  primary_alb_zone       = \"$PRIMARY_ALB_ZONE\""
echo "  primary_alb_arn_suffix = \"$PRIMARY_ALB_ARN_SUFFIX\""
echo "  primary_tg_arn_suffix  = \"$PRIMARY_TG_ARN_SUFFIX\""
echo "  dr_alb_dns             = \"$DR_ALB_DNS\""
echo "  dr_alb_zone            = \"$DR_ALB_ZONE\""
echo "  dr_asg_name            = \"$DR_ASG_NAME\""
echo "  dr_replica_id          = \"$DR_REPLICA_ID\""
echo ""
echo "After filling shared/terraform.tfvars, run:"
echo "  cd shared/ && terraform init && terraform apply"

echo ""
echo "======================================================"
echo "  Deployment complete (except shared/ — see above)"
echo "======================================================"
