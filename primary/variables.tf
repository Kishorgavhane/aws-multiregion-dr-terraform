variable "region" {
  default     = "ap-south-1"
  description = "Primary AWS region"
}

variable "project_name" {
  default     = "dr-demo"
  description = "Project name prefix for all resources"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "CIDR block for primary VPC"
}

variable "ami_id" {
  default     = "ami-0f5ee92e2d63afc18"
  description = "Amazon Linux 2023 AMI for ap-south-1"
}

variable "db_password" {
  sensitive   = true
  description = "RDS master password — set in terraform.tfvars"
}

variable "dr_bucket_arn" {
  description = "ARN of DR S3 bucket in ap-southeast-1 (from dr/ terraform output dr_bucket_arn)"
}

variable "aws_profile" {
  default     = "default"
  description = "AWS CLI profile to use"
}
