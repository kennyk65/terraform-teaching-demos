# Replica of AWS Architecting Lab 2

provider "aws" {
  region = "us-west-2"  # Change to your desired AWS region
  # Add any necessary AWS credentials configuration here
  default_tags {
    tags = local.default_tags
  }
}

variable "stack_name" {
  type        = string
  default     = "Arch7Lab3"
  description = "Common name used in resources built by this configuration"
}

variable "lab2_stack_name" {
  description = "The name of the stack from Lab 2"
  default     = "Arch7Lab2"
}

# Define default tags
locals {
  default_tags = {
    Stack = "${var.stack_name}"
  }
}

data "aws_ami" "latest_ami" {
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  owners = ["amazon"]
}


resource "aws_security_group" "lab_alb_security_group" {
  name_prefix = "LabALBSecurityGroup"
  description = "ALB Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LabALBSecurityGroup"
  }
}

resource "aws_security_group" "db_security_group" {
  name_prefix = "LabDBSecurityGroup"
  description = "Lab DB Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LabDBSecurityGroup"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "LabDBSubnetGroup"
  description = "Lab DB Subnet Group"

  subnet_ids = [
    module.vpc.private_subnet_ids[0],
    module.vpc.private_subnet_ids[1]
  ]
}



resource "aws_db_instance" "lab_db_instance" {
  allocated_storage    = 5
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.small"
  name                 = "labdatabase"
  username             = "admin"
  password             = "admin123"
  multi_az             = false
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.db_security_group.id
  ]
}

resource "aws_lb" "alb" {
  name               = "${var.lab2_stack_name}-LabAppALB"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.lab_alb_security_group.id]
  subnets            = [
    module.vpc.public_subnet_ids[0],
    module.vpc.public_subnet_ids[1]
  ]
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    status_code      = "200"
    content_type     = "text/plain"
    message_body     = "OK"
  }
}

resource "aws_lb_target_group" "alb_target_group" {
  name     = "${var.lab2_stack_name}-ALBTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path        = "/"
    port        = "80"
    protocol    = "HTTP"
    matcher     = "200"
    target_type = "instance"
  }
}

resource "aws_instance" "app_instance" {
  ami           = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  subnet_id           = module.vpc.public_subnet_ids[0]
  associate_public_ip = true
  security_groups    = [aws_security_group.lab_alb_security_group.id]

  user_data = <<-EOF
    #!/bin/bash
    yum -y update
    cd /tmp
    yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    yum install -y httpd mysql
    amazon-linux-extras install -y php7.2
    wget https://us-west-2-tcprod.s3.us-west-2.amazonaws.com/courses/ILT-TF-200-ARCHIT/v7.0.0/lab-4-HA/scripts/inventory-app.zip
    unzip inventory-app.zip -d /var/www/html/
    wget https://github.com/aws/aws-sdk-php/releases/download/3.62.3/aws.zip
    unzip -q aws.zip -d /var/www/html
    un="admin"
    pw="admin123"
    ep="${aws_db_instance.lab_db_instance.endpoint}"
    db="labdatabase"
    sed -i "s/DBENDPOINT/$ep/g" /var/www/html/get-parameters.php
    sed -i "s/DBNAME/$db/g" /var/www/html/get-parameters.php
    sed -i "s/DBUSERNAME/$un/g" /var/www/html/get-parameters.php
    sed -i "s/DBPASSWORD/$pw/g" /var/www/html/get-parameters.php
    systemctl start httpd.service
    systemctl enable httpd.service
EOF

  tags = {
    Name = "App Instance"
  }
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.lab2_stack_name}-EC2-SSM-Role"
  role = aws_iam_role.instance_role.name
}

output "db_endpoint" {
  description = "Endpoint of RDS DB"
  value       = aws_db_instance.lab_db_instance.endpoint
}

output "alb_target_group" {
  description = "ALB Target Group"
  value       = aws_lb_target_group.alb_target_group.arn
}

output "rds_db_name" {
  description = "RDS Database Name"
  value       = "labdatabase"
}

output "rds_master_user" {
  description = "Username"
  value       = "admin"
}

output "rds_password" {
  description = "Password"
  value       = "admin123"
}

output "elb_endpoint" {
  description = "The URL for our Elastic Load Balancer"
  value       = aws_lb.alb.dns_name
}
