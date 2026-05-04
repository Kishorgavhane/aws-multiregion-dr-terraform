provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "dr" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-dr-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dr.id
  tags   = { Name = "${var.project_name}-dr-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.dr.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-dr-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.dr.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.project_name}-dr-private-${count.index}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-dr-nat-eip" }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-dr-ngw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dr.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-dr-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.dr.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }
  tags = { Name = "${var.project_name}-dr-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Security Groups ──────────────────────────────────────────────────────────

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-dr-alb-sg"
  description = "Allow HTTP/HTTPS to DR ALB"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-dr-alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-dr-app-sg"
  description = "Allow HTTP from DR ALB only"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-dr-app-sg" }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-dr-rds-sg"
  description = "Allow MySQL from DR app tier"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
  tags = { Name = "${var.project_name}-dr-rds-sg" }
}

# ── DR Application Load Balancer ─────────────────────────────────────────────

resource "aws_lb" "dr" {
  name               = "${var.project_name}-dr-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]
  tags               = { Name = "${var.project_name}-dr-alb" }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-dr-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }
  tags = { Name = "${var.project_name}-dr-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.dr.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── DR EC2 Launch Template & ASG (starts at 0 capacity) ──────────────────────

resource "aws_launch_template" "dr_app" {
  name_prefix   = "${var.project_name}-dr-"
  image_id      = var.ami_id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    mkdir -p /var/www/html
    cat > /var/www/html/health <<'HTML'
    {"status":"healthy","region":"ap-southeast-1","env":"dr","mode":"ACTIVE"}
    HTML
    cat > /var/www/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head><title>DR Demo</title></head>
    <body style="font-family:sans-serif;padding:40px">
      <h1>DR Demo App</h1>
      <h2 style="color:orange">DR REGION — ap-southeast-1 (Singapore)</h2>
      <p>Status: <strong>DR ACTIVE</strong></p>
    </body>
    </html>
    HTML
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-dr-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "dr" {
  name                = "${var.project_name}-dr-asg"
  min_size            = 0  # KEY: Zero capacity — passive standby
  max_size            = 4
  desired_capacity    = 0  # Lambda sets this to 2 during failover
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.dr_app.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-dr-app"
    propagate_at_launch = true
  }
}

# ── RDS Cross-Region Read Replica ────────────────────────────────────────────

resource "aws_db_subnet_group" "dr" {
  name       = "${var.project_name}-dr-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.project_name}-dr-db-subnet" }
}

resource "aws_db_instance" "dr_replica" {
  identifier             = "${var.project_name}-dr-replica"
  replicate_source_db    = var.primary_rds_arn  # Cross-region replica
  instance_class         = "db.t3.micro"
  db_subnet_group_name   = aws_db_subnet_group.dr.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # Do NOT set db_name, username, password — inherited from source
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
  publicly_accessible     = false

  tags = { Name = "${var.project_name}-dr-replica", Role = "replica" }
}

# ── DR S3 Destination Bucket (CRR target) ────────────────────────────────────

resource "aws_s3_bucket" "dr_assets" {
  bucket        = "${var.project_name}-dr-assets-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-dr-assets" }
}

resource "aws_s3_bucket_versioning" "dr" {
  bucket = aws_s3_bucket.dr_assets.id
  versioning_configuration { status = "Enabled" }
}
