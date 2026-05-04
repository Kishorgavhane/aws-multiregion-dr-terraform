provider "aws" {
  region  = "us-east-1"  # Route 53 health checks must be created in us-east-1
  profile = var.aws_profile
}

# ── SNS Topic for DR Alerts ───────────────────────────────────────────────────

resource "aws_sns_topic" "dr_alerts" {
  name = "dr-failover-alerts"
  tags = { Name = "dr-failover-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "lambda_trigger" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.failover.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.dr_alerts.arn
}

# ── IAM Role for Lambda ───────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_failover" {
  name = "dr-lambda-failover-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_failover.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dr_policy" {
  name = "lambda-dr-permissions"
  role = aws_iam_role.lambda_failover.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds:PromoteReadReplica", "rds:DescribeDBInstances", "rds:ModifyDBInstance"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["autoscaling:UpdateAutoScalingGroup", "autoscaling:DescribeAutoScalingGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.dr_alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda Function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "failover" {
  function_name = "dr-failover-handler"
  runtime       = "python3.11"
  handler       = "failover.lambda_handler"
  role          = aws_iam_role.lambda_failover.arn
  filename      = "${path.module}/../lambda/failover.zip"
  timeout       = 300
  memory_size   = 128

  environment {
    variables = {
      DR_REGION       = "ap-southeast-1"
      DR_ASG_NAME     = var.dr_asg_name
      DR_REPLICA_ID   = var.dr_replica_id
      DR_ASG_CAPACITY = "2"
      SNS_TOPIC_ARN   = aws_sns_topic.dr_alerts.arn
    }
  }

  tags = { Name = "dr-failover-handler" }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/dr-failover-handler"
  retention_in_days = 30
}

# ── Route 53 Health Check on Primary ALB ─────────────────────────────────────

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "10"

  tags = { Name = "dr-demo-primary-health-check" }
}

# ── Route 53 Failover Records ─────────────────────────────────────────────────

resource "aws_route53_record" "primary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy { type = "PRIMARY" }
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "dr" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy { type = "SECONDARY" }
  set_identifier = "dr"

  alias {
    name                   = var.dr_alb_dns
    zone_id                = var.dr_alb_zone
    evaluate_target_health = true
  }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "dr-primary-alb-unhealthy"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "30"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Primary ALB has unhealthy hosts — triggers DR failover"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = var.primary_alb_arn_suffix
    TargetGroup  = var.primary_tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = { Name = "dr-primary-alb-unhealthy" }
}

resource "aws_cloudwatch_metric_alarm" "rds_replica_lag" {
  alarm_name          = "dr-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "60"
  alarm_description   = "Cross-region RDS replica lag > 60s — RPO at risk"

  dimensions = { DBInstanceIdentifier = var.dr_replica_id }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]

  tags = { Name = "dr-replica-lag-high" }
}
