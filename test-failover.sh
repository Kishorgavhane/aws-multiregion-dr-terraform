#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# DR Failover Test Script — validates RTO
# Usage: ./test-failover.sh app.yourdomain.com
# ─────────────────────────────────────────────────────────────────

DOMAIN=${1:-"app.yourdomain.com"}
PRIMARY_ASG="dr-demo-primary-asg"
DR_ASG="dr-demo-dr-asg"
START=$(date +%s)

echo "======================================================"
echo "  DR Failover Test"
echo "  Domain: $DOMAIN"
echo "  Start:  $(date)"
echo "======================================================"

echo ""
echo "[PRE-CHECK] Verifying primary is serving..."
HEALTH=$(curl -s --max-time 10 http://$DOMAIN/health 2>/dev/null)
echo "Primary health: $HEALTH"

echo ""
echo "[T+0:00] Simulating primary failure — scaling ASG to 0..."
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $PRIMARY_ASG \
  --min-size 0 --desired-capacity 0 \
  --region ap-south-1

echo "Primary ASG scaled to 0. Starting RTO clock..."

echo ""
echo "[MONITORING] Polling $DOMAIN every 10 seconds..."
echo "Press Ctrl+C to stop after DR is confirmed."
echo ""

FAILOVER_TIME=""
while true; do
  NOW=$(date +%s)
  ELAPSED=$(( NOW - START ))
  MINS=$(( ELAPSED / 60 ))
  SECS=$(( ELAPSED % 60 ))
  
  RESPONSE=$(curl -s --max-time 5 http://$DOMAIN/health 2>/dev/null || echo "no_response")
  
  printf "T+%02d:%02d | %s\n" $MINS $SECS "$RESPONSE"
  
  # Check if DR region is responding
  if echo "$RESPONSE" | grep -q "ap-southeast-1"; then
    echo ""
    echo "======================================================"
    echo "  DR ACTIVE — Singapore is serving traffic!"
    printf "  RTO ACHIEVED: %02d min %02d sec\n" $MINS $SECS
    echo "======================================================"
    break
  fi
  
  sleep 10
done

echo ""
echo "[POST-FAILOVER] Checking RDS replica promotion status..."
aws rds describe-db-instances \
  --db-instance-identifier dr-demo-dr-replica \
  --region ap-southeast-1 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,IsReplica:ReadReplicaSourceDBInstanceIdentifier,Endpoint:Endpoint.Address}' \
  --output table

echo ""
echo "Test complete. Record your RTO for the resume!"
echo "To restore primary: cd primary/ && terraform apply"
