output "sns_topic_arn" {
  description = "SNS topic ARN for DR alerts"
  value       = aws_sns_topic.dr_alerts.arn
}

output "lambda_function_arn" {
  description = "DR failover Lambda ARN"
  value       = aws_lambda_function.failover.arn
}

output "health_check_id" {
  description = "Route 53 health check ID — use to monitor primary status"
  value       = aws_route53_health_check.primary.id
}

output "primary_dns_record" {
  description = "Active DNS record pointing to primary"
  value       = aws_route53_record.primary.fqdn
}
