
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
    key            = "jenkins-on-ec2/default/terraform.tfstate"
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
  default     = "jenkins-on-ec2"
  description = "Common name used in resources built by this configuration"
}

# Define default tags
locals {
  default_tags = {
    Stack = "${var.stack_name}"
    Workspace = "${terraform.workspace}"
  }
}


# Data source to look up the latest Amazon Linux 2023 AMI for x86_64 architecture
data "aws_ami" "latest_ami" {
  most_recent = true
  owners      = ["amazon"] # Official AWS account ID for Amazon Linux AMIs

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Finds the latest Amazon Linux 2023 AMI for x86_64
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}



# Security Group for Jenkins
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-security-group"
  description = "Allow Jenkins (8080) inbound traffic"
  # Ingress rule for Jenkins (port 8080)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Allow Jenkins HTTP from anywhere"
  }
  # Egress rule to allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name = "jenkins-security-group"
  }
}

# EC2 Instance for Jenkins
resource "aws_instance" "jenkins_server" {
  ami           = data.aws_ami.latest_ami.id  # Use the AMI ID from the data source
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  user_data = <<-EOF
    #!/bin/bash
    set -e # Exit immediately if a command exits with a non-zero status
    set -x # Print commands and their arguments as they are executed, this helps in debugging

    echo "Starting Jenkins EC2 setup on Amazon Linux 2023..."

    # Update package lists and install prerequisites using dnf
    echo "Updating package lists and installing Java (Corretto 17), wget, curl, gnupg2..."
    sudo dnf update -y
    sudo dnf install -y java-17-amazon-corretto wget gnupg2

    # Add Jenkins repository for RedHat-based systems
    echo "Adding Jenkins DNF repository key..."
    sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

    # Install Jenkins
    echo "Installing Jenkins..."
    sudo dnf install -y jenkins

    # Start and enable Jenkins service
    echo "Enabling and starting Jenkins service..."
    sudo systemctl enable jenkins
    sudo systemctl start jenkins

    # Wait for Jenkins to be somewhat up (port 8080 listening)
    echo "Waiting for Jenkins to start and listen on port 8080. This might take a few minutes..."
    until sudo ss -tunl | grep -q 8080; do
        echo "Jenkins port 8080 not yet listening, waiting 10 seconds..."
        sleep 10
    done
    echo "Jenkins port 8080 is now listening. Proceeding with plugin installation."

    echo "Please allow a few more minutes for Jenkins to fully come online and initialize plugins. If plugins do not appear, check Jenkins logs (e.g., sudo journalctl -u jenkins.service) or the Jenkins UI for plugin management and errors."
  EOF

  tags = {
    Name = "jenkins-server"
  }
}


# Output the public IP address of the Jenkins instance
output "jenkins_public_ip" {
  description = "The public IP address of the Jenkins EC2 instance"
  value = "http://${aws_instance.jenkins_server.public_ip}:8080"
}
