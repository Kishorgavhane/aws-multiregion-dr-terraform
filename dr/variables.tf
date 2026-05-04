variable "region" {
  default     = "ap-southeast-1"
  description = "DR AWS region"
}

variable "project_name" {
  default     = "dr-demo"
  description = "Project name prefix for all resources"
}

variable "vpc_cidr" {
  default     = "10.1.0.0/16"
  description = "CIDR block for DR VPC (must not overlap with primary 10.0.0.0/16)"
}

variable "ami_id" {
  default     = "ami-0c55b159cbfafe1f0"
  description = "Amazon Linux 2023 AMI for ap-southeast-1"
}

variable "db_password" {
  sensitive   = true
  description = "RDS password — must match primary. Set in terraform.tfvars"
}

variable "primary_rds_arn" {
  description = "ARN of primary RDS instance (from: cd primary/ && terraform output rds_arn)"
}

variable "aws_profile" {
  default     = "default"
  description = "AWS CLI profile to use"
}
