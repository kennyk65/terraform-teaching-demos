provider "aws" {
  region = "us-west-2"  # Change to your desired AWS region
  # Add any necessary AWS credentials configuration here
}

variable "stack_name" {
  type        = string
  default     = "Arch7Lab2"
  description = "Common name used in resources built by this configuration"
}

data "aws_ami" "latest_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

# Resources
resource "aws_vpc" "lab_vpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "Lab VPC",
    Stack = "${var.stack_name}"
  }
}

resource "aws_internet_gateway" "lab_igw" {
  tags = {
    Name = "${var.stack_name}-LabIGW"
  }
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
    Name = "NAT-${var.stack_name}"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.2.0/23"
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.lab_vpc.id
  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.lab_vpc.id
  tags = {
    Name = "Private Route Table"
  }
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
  tags = {
    Name = "Public SG"
  }
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
  tags = {
    Name = "Private SG"
  }
}

resource "aws_instance" "public_instance" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  subnet_id     = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.public_security_group.id]
  user_data = <<-EOF
          #!/bin/bash
          yum update -y &&
          amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2 &&
          yum install -y httpd &&
          systemctl enable httpd.service
          systemctl start httpd
          cd /var/www/html
          wget  https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-TF-200-ARCHIT/v7.0.0/lab-2-VPC/scripts/instanceData.zip
          unzip instanceData.zip
  EOF
  tags = {
    Name = "Public Instance"
  }
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.stack_name}-EC2-SSM-Role"
  role = aws_iam_role.instance_role.name
}

resource "aws_iam_role" "instance_role" {
  name = "${var.stack_name}-EC2-SSM-Role"
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
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

resource "aws_instance" "private_instance" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_security_group.id]
  tags = {
    Name = "Private Instance"
  }
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
