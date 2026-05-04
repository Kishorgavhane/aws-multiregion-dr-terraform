output "dr_alb_dns_name" {
  description = "DR ALB DNS name — use in Route 53 secondary alias record"
  value       = aws_lb.dr.dns_name
}

output "dr_alb_zone_id" {
  description = "DR ALB hosted zone ID — use in Route 53 secondary alias record"
  value       = aws_lb.dr.zone_id
}

output "dr_alb_arn_suffix" {
  description = "DR ALB ARN suffix"
  value       = aws_lb.dr.arn_suffix
}

output "dr_asg_name" {
  description = "DR ASG name — Lambda scales this during failover"
  value       = aws_autoscaling_group.dr.name
}

output "dr_replica_identifier" {
  description = "DR RDS replica identifier — Lambda promotes this during failover"
  value       = aws_db_instance.dr_replica.identifier
}

output "dr_replica_endpoint" {
  description = "DR RDS replica endpoint (available after promotion)"
  value       = aws_db_instance.dr_replica.endpoint
}

output "dr_bucket_arn" {
  description = "DR S3 bucket ARN — pass to primary/ as dr_bucket_arn variable"
  value       = aws_s3_bucket.dr_assets.arn
}

output "dr_bucket_name" {
  description = "DR S3 bucket name"
  value       = aws_s3_bucket.dr_assets.bucket
}

output "dr_vpc_id" {
  description = "DR VPC ID"
  value       = aws_vpc.dr.id
}
