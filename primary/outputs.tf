output "alb_dns_name" {
  description = "Primary ALB DNS name — use in Route 53 alias record"
  value       = aws_lb.primary.dns_name
}

output "alb_zone_id" {
  description = "Primary ALB hosted zone ID — use in Route 53 alias record"
  value       = aws_lb.primary.zone_id
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix — use in CloudWatch dimensions"
  value       = aws_lb.primary.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target Group ARN suffix — use in CloudWatch dimensions"
  value       = aws_lb_target_group.app.arn_suffix
}

output "rds_arn" {
  description = "Primary RDS ARN — pass to dr/ as primary_rds_arn variable"
  value       = aws_db_instance.primary.arn
}

output "rds_endpoint" {
  description = "Primary RDS endpoint"
  value       = aws_db_instance.primary.endpoint
}

output "asg_name" {
  description = "Primary ASG name"
  value       = aws_autoscaling_group.primary.name
}

output "vpc_id" {
  description = "Primary VPC ID"
  value       = aws_vpc.main.id
}

output "primary_bucket_name" {
  description = "Primary S3 bucket name"
  value       = aws_s3_bucket.primary.bucket
}
