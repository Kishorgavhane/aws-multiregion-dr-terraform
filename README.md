# AWS Multi-Region Disaster Recovery — Terraform

Active-Passive DR architecture across **ap-south-1 (Mumbai) → ap-southeast-1 (Singapore)**

**Validated RTO < 15 minutes | RPO < 5 minutes**

---

## Architecture

```
Route 53 Health-Check Failover
        |
   _____|_____
  |           |
PRIMARY      DR REGION
ap-south-1   ap-southeast-1
  ALB          ALB (passive)
  EC2 ASG      EC2 ASG (0 → 2 on failover)
  RDS Multi-AZ RDS Read Replica (promoted on DR)
  S3 Bucket    S3 Replica (CRR)
  CloudWatch → SNS → Lambda (auto-failover)
```

## Stack
- Terraform >= 1.6
- AWS Route 53, RDS MySQL 8.0, EC2 ASG, ALB
- S3 Cross-Region Replication (CRR)
- Lambda (Python 3.11), CloudWatch, SNS
- SSM Automation Runbook

## Deployment Order

```bash
# 1. DR bucket first
cd dr/ && terraform init && terraform apply -target=aws_s3_bucket.dr_assets

# 2. Primary region
cd ../primary/ && terraform init && terraform apply -var-file=terraform.tfvars

# 3. Full DR region
cd ../dr/ && terraform apply -var-file=terraform.tfvars

# 4. Package Lambda
cd ../lambda/ && zip -r failover.zip failover.py

# 5. Shared (Route 53, Lambda, CloudWatch, SNS)
cd ../shared/ && terraform init && terraform apply -var-file=terraform.tfvars
```

## Failover Test

```bash
# Break primary
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name dr-demo-primary-asg \
  --min-size 0 --desired-capacity 0 --region ap-south-1

# Watch recovery
while true; do
  curl -s http://app.yourdomain.com/health
  sleep 10
done
```

## Cleanup

```bash
cd shared/  && terraform destroy
cd ../dr/   && terraform destroy
cd ../primary/ && terraform destroy
```

## Resume Bullets

- Designed a DR architecture across Mumbai and Singapore using Terraform; ran multiple failover simulations and confirmed RTO stayed under 15 min, RPO under 5 min each time
- Wired Route 53 health checks to an RDS cross-region replica and wrote a Lambda that kicks in the moment CloudWatch flags the primary down — the whole promotion happens without anyone logging in
- Used S3 CRR to keep static assets in sync across regions and tied the whole DR process into an SSM Automation document so failover is repeatable and auditable
- Kept DR costs near zero — passive region runs at zero EC2 capacity and only spins up through an SNS-triggered Lambda when an actual failover happens
