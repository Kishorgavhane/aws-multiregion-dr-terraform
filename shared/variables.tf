variable "aws_profile" {
  default     = "default"
  description = "AWS CLI profile"
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for your domain"
}

variable "domain_name" {
  description = "DNS record name e.g. app.yourdomain.com"
}

variable "alert_email" {
  description = "Email address to receive DR failover alerts"
}

variable "primary_alb_dns" {
  description = "Primary ALB DNS name (from: cd primary/ && terraform output alb_dns_name)"
}

variable "primary_alb_zone" {
  description = "Primary ALB zone ID (from: cd primary/ && terraform output alb_zone_id)"
}

variable "primary_alb_arn_suffix" {
  description = "Primary ALB ARN suffix (from: cd primary/ && terraform output alb_arn_suffix)"
}

variable "primary_tg_arn_suffix" {
  description = "Primary Target Group ARN suffix (from: cd primary/ && terraform output target_group_arn_suffix)"
}

variable "dr_alb_dns" {
  description = "DR ALB DNS name (from: cd dr/ && terraform output dr_alb_dns_name)"
}

variable "dr_alb_zone" {
  description = "DR ALB zone ID (from: cd dr/ && terraform output dr_alb_zone_id)"
}

variable "dr_asg_name" {
  description = "DR ASG name (from: cd dr/ && terraform output dr_asg_name)"
}

variable "dr_replica_id" {
  description = "DR RDS replica identifier (from: cd dr/ && terraform output dr_replica_identifier)"
}
