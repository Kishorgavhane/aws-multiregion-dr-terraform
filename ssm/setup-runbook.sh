#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# Create SSM Automation Runbook
# Run after deploying all Terraform
# ─────────────────────────────────────────────────────────────────

echo "Creating SSM Automation document..."

aws ssm create-document \
  --name "DR-Failover-Runbook" \
  --document-type "Automation" \
  --document-format "JSON" \
  --content file://ssm/dr-runbook.json \
  --region ap-south-1

echo "SSM Runbook created: DR-Failover-Runbook"
echo ""
echo "To run the runbook manually:"
echo "  aws ssm start-automation-execution \\"
echo "    --document-name DR-Failover-Runbook \\"
echo "    --parameters DRASGName=dr-demo-dr-asg,DRReplicaId=dr-demo-dr-replica \\"
echo "    --region ap-south-1"
