
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80.0, < 6.0.0" # Not tested beyond v5.
    }
  }
  backend "s3" {
    bucket         = "kk-admin-terraform"
    key            = "MinimalEc2Deploy/default/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  default_tags {
    tags = local.default_tags
  }
}

variable "stack_name" {
  type        = string
  default     = "MinimalEc2Deploy"
  description = "Common name used in resources built by this configuration"
}

# Define default tags
locals {
  default_tags = {
    Stack = "${var.stack_name}"
    Workspace = "${terraform.workspace}"
  }
}

# Automatically lookup the most recent AMI with the given name
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

resource "aws_instance" "example" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t2.micro"
  user_data     = <<-EOF
        #!/bin/bash
        yum -y update
        yum install java-21-amazon-corretto -y
        dnf update -y
        dnf install java-21-amazon-corretto -y
        cd /tmp
        wget https://kk-uploads-oregon.s3.amazonaws.com/spring-cloud-aws-environment-demo-17.jar -q
        mv *.jar app.jar
        java -jar app.jar --server.port=80
        EOF  
  vpc_security_group_ids = [aws_security_group.allow_80.id]
}


# Create a security group allowing ingress on 80:
resource "aws_security_group" "allow_80" {
  name        = "allow_80"
  description = "Allow ingress on 80"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Must be explicitly defined in terraform
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }  
}