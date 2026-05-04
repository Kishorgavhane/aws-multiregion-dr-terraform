provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-primary-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-primary-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-primary-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.project_name}-primary-private-${count.index}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-primary-nat-eip" }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-primary-ngw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-primary-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }
  tags = { Name = "${var.project_name}-primary-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Security Groups ──────────────────────────────────────────────────────────

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-primary-alb-sg"
  description = "Allow HTTP/HTTPS to ALB"
  vpc_id      = aws_vpc.main.id

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
  tags = { Name = "${var.project_name}-primary-alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-primary-app-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.main.id

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
  tags = { Name = "${var.project_name}-primary-app-sg" }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-primary-rds-sg"
  description = "Allow MySQL from app tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
  tags = { Name = "${var.project_name}-primary-rds-sg" }
}

# ── Application Load Balancer ────────────────────────────────────────────────

resource "aws_lb" "primary" {
  name               = "${var.project_name}-primary-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]
  tags               = { Name = "${var.project_name}-primary-alb" }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-primary-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }
  tags = { Name = "${var.project_name}-primary-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.primary.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── EC2 Launch Template & Auto Scaling Group ─────────────────────────────────

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-primary-"
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
    {"status":"healthy","region":"ap-south-1","env":"primary"}
    HTML
    cat > /var/www/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head><title>DR Demo</title></head>
    <body style="font-family:sans-serif;padding:40px">
      <h1>DR Demo App</h1>
      <h2 style="color:green">PRIMARY REGION — ap-south-1 (Mumbai)</h2>
      <p>Status: <strong>ACTIVE</strong></p>
    </body>
    </html>
    HTML
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-primary-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "primary" {
  name                = "${var.project_name}-primary-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-primary-app"
    propagate_at_launch = true
  }
}

# ── RDS MySQL Multi-AZ ───────────────────────────────────────────────────────

resource "aws_db_subnet_group" "primary" {
  name       = "${var.project_name}-primary-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.project_name}-primary-db-subnet" }
}

resource "aws_db_instance" "primary" {
  identifier              = "${var.project_name}-primary-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  multi_az                = true
  db_name                 = "appdb"
  username                = "admin"
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:03:00-Mon:04:00"
  deletion_protection     = false
  skip_final_snapshot     = true
  publicly_accessible     = false

  tags = { Name = "${var.project_name}-primary-db", Role = "primary" }
}

# ── S3 Source Bucket + CRR ───────────────────────────────────────────────────

resource "aws_iam_role" "s3_replication" {
  name = "${var.project_name}-s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.project_name}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = "${var.dr_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket" "primary" {
  bucket        = "${var.project_name}-primary-assets-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-primary-assets" }
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_replication_configuration" "crr" {
  depends_on = [aws_s3_bucket_versioning.primary]
  bucket     = aws_s3_bucket.primary.id
  role       = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-all-objects"
    status = "Enabled"
    destination {
      bucket        = var.dr_bucket_arn
      storage_class = "STANDARD"
    }
  }
}
