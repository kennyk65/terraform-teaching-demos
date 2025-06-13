
# Replica of AWS Architecting Lab 2

# define provider and acceptable versions.
# Use remote state management instead of local files
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 5.80.0, < 6.0.0"    # Not tested beyond v5.
    }
  }
  backend "s3" {
    bucket         = "kk-admin-terraform"
    key            = "arch7-lab2/default/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }  
}


provider "aws" {
  # region = "us-west-2"  # Change to your desired AWS region
  # Add any necessary AWS credentials configuration here
  default_tags {
    tags = local.default_tags
  }
}

variable "stack_name" {
  type        = string
  default     = "Arch7Lab2"
  description = "Common name used in resources built by this configuration"
}

# Define default tags
locals {
  default_tags = {
    Stack = "${var.stack_name}"
    Workspace = "${terraform.workspace}"
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

# Resources
resource "aws_vpc" "lab_vpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "LabVPC-${var.stack_name}"  }
}

resource "aws_internet_gateway" "lab_igw" {
  tags = {
    Name = "LabIGW-${var.stack_name}"  }
  vpc_id = aws_vpc.lab_vpc.id
}
# Note - No gateway attachment in terraform?


resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "NAT-${var.stack_name}"  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnetA-${var.stack_name}"  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.2.0/23"
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  tags = {
    Name = "PrivateSubnetA-${var.stack_name}"  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.lab_vpc.id
  tags = {
    Name = "PublicRouteTable-${var.stack_name}"  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab_igw.id
  # Wait until the IGW is attached to the VPC:
  depends_on = [aws_internet_gateway.lab_igw]  
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.lab_vpc.id
  tags = {
    Name = "PrivateRouteTable-${var.stack_name}"  }
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "public_security_group" {
  name_prefix = "Public SG"
  vpc_id      = aws_vpc.lab_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # WARNING: TERRAFORM REQUIRES EXPLICIT DEFINITION OF EGRESS ROUTE
  egress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 0
    protocol  = "-1"
    to_port   = 0
  }
  tags = {
    Name = "PublicSG-${var.stack_name}"  }
}

resource "aws_security_group" "private_security_group" {
  name_prefix = "Private SG"
  vpc_id      = aws_vpc.lab_vpc.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.public_security_group.id]
  }
  # WARNING: TERRAFORM REQUIRES EXPLICIT DEFINITION OF EGRESS ROUTE
  egress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 0
    protocol  = "-1"
    to_port   = 0
  }
  tags = {
    Name = "PrivateSG-${var.stack_name}"  }
}

resource "aws_instance" "public_instance" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  subnet_id     = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.public_security_group.id]
  user_data = <<-EOF
          #!/bin/bash
          # To connect to your EC2 instance and install the Apache web server with PHP
          yum update -y
          yum install -y httpd php8.1
          systemctl enable httpd.service
          systemctl start httpd
          cd /var/www/html
          wget  https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-TF-200-ARCHIT/v7.5.0.prod-b5a35238/lab-2-VPC/scripts/instanceData.zip
          unzip instanceData.zip
  EOF
  # Wait until the public route is attached to the public route table:
  depends_on = [aws_internet_gateway.lab_igw]  
  metadata_options {
    http_tokens = "optional"
  }
  tags = {
    Name = "PublicInstance-${var.stack_name}"  }
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2SSMRole-${var.stack_name}"
  role = aws_iam_role.instance_role.name
  tags = {
    Stack = "Ec2SsmRole-${var.stack_name}"
  }
}

resource "aws_iam_role" "instance_role" {
  name = "EC2-SSM-Role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = {
    Stack = "EC2-SSM-Role-${var.stack_name}"
  }
}
resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_instance" "private_instance" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_security_group.id]
  tags = {
    Name = "PrivateInstance-${var.stack_name}"  }
}

# The following resources are only needed to support later labs:
resource "aws_subnet" "public_subnetb" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.6.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnetB-${var.stack_name}"  }
}

resource "aws_subnet" "private_subnetb" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.4.0/23"
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  tags = {
    Name = "PrivateSubnetB-${var.stack_name}"  }
}

resource "aws_route_table_association" "public_subnet_b_association" {
  subnet_id      = aws_subnet.public_subnetb.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_b_association" {
  subnet_id      = aws_subnet.private_subnetb.id
  route_table_id = aws_route_table.private_route_table.id
}



# Data Sources
data "aws_availability_zones" "available" {}

# Outputs
output "PublicInstanceIP" {
  description = "The Public IP address for the public EC2 instance."
  value       = aws_instance.public_instance.public_ip
}

output "PrivateInstanceIP" {
  description = "The Private IP address for the private EC2 instance."
  value       = aws_instance.private_instance.private_ip
}

output "VPC" {
  description = "VPC of the base network"
  value       = aws_vpc.lab_vpc.id
}

output "PublicSubnet" {
  description = "Public Subnet"
  value       = aws_subnet.public_subnet.id
}

output "PrivateSubnet" {
  description = "Private Subnet"
  value       = aws_subnet.private_subnet.id
}

output "PublicInstance" {
  description = "The EC2 instance ID of the public EC2 instance."
  value       = aws_instance.public_instance.id
}

output "PublicSecurityGroup" {
  description = "The security group for web instances."
  value       = aws_security_group.public_security_group.id
}

output "EC2InstanceProfile" {
  description = "The Instance profile used for SSM Agent on EC2 instances."
  value       = aws_iam_instance_profile.ec2_instance_profile.id
}
