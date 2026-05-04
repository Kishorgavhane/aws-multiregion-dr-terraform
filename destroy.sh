#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# AWS Multi-Region DR — Full Destroy Script
# Run this after testing to avoid ongoing charges
# ─────────────────────────────────────────────────────────────────
set -e

echo "======================================================"
echo "  WARNING: This will destroy ALL DR project resources"
echo "======================================================"
read -p "Are you sure? Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

echo "[1/3] Destroying shared resources..."
cd shared/ && terraform destroy -auto-approve

echo "[2/3] Destroying DR region..."
cd ../dr/ && terraform destroy -auto-approve

echo "[3/3] Destroying Primary region..."
cd ../primary/ && terraform destroy -auto-approve

echo ""
echo "All resources destroyed. Verify in AWS console."
