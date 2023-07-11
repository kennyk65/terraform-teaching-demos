#  This template illustrates three separate ways to connect two VPCs,
#  VPC Peering, Transit Gateway, and VPC (Interface) Endpoints.
#  It launches EC2 instances in the provider and consumer VPCs to
#  make the connectivity easier to demonstrate.  It also provides a 
#  quick link to the network reachability page in the management console 
#  to graphically show the network components.
#
#  To demonstrate VPC Endpoints / Private Link, create the stack with option 1.
#  The provider instance hosts a small web service (Python/Flask in a Docker container)
#  Which can be called via the VPC Endpoint's DNS name.  Find the VPC endpoint and copy 
#  one of it's DNS names.  Use the session manager link to connect to the consumer instance.
#  Call the web service like this:  curl http://<DNSNAME>/api?value=2 .
#  
#  To demonstrate VPC peering, create the stack with option 2.  Find the 
#  private IP address of the provider instance.  Use
#  the session manager link to connect to the consumer instance.  Ping the
#  destination instance like this:   ping -c 6 <IP-ADDRESS>     or call the web service 
#  like this:  curl http://<IP-ADDRESS>/api?value=2
#
#  To demonstrate Transit Gateway, create the stack with option 3.  Follow the
#  same demo ideas for peering.
#
#  Optional: For any of these options, use the link in stack output to open
#  VPC / Network Manager / Reachability Analyzer.  Enter source as consumer 
#  instance, target as provider instance.


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.7.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-west-2"
}

variable "ami_id" {
  type = string
  default = "ami-04d0def24be0d27d6"     # TODO - DYNAMICALLY LOOK UP
  description = "Amazon Linux 2 AMI ID for the given region"
}

variable "region" {
  type = string
  default = "us-west-2"        #   TODO - DYNAMICALLY LOOK UP.  Should be available from provider above
  description = "The region to use."
}

variable "availability_zone" {
  type = string
  default = "us-west-2a"        #   TODO - DYNAMICALLY LOOK UP
  description = "The availability zone to use within the region."
}

variable "stack_name" {
    type = string
    default = "privateLinkDemo"
    description = "Common name used in resources built by this configuration"
}

variable "docker_image" {
    type = string
    default = "public.ecr.aws/kkrueger/flask-api:1"
    description = "Image to use for a container.  Can be from DockerHub or include registry URL for a different source (repository-url/image:tag)."
}

variable "connection_type" {
    type = number
    default = 1
    description = "1=Private Link,  2=VPC Peering,  3=Transit Gateway"
}

# These variables allow us to selectively create private link, peering, 
# or transit gateway resources depending on the demo being run:
locals {
  create_private_link    = (var.connection_type == 1 ? 1 : 0 )
  create_peering         = (var.connection_type == 2 ? 1 : 0 )
  create_transit_gateway = (var.connection_type == 3 ? 1 : 0 )
}

#  Provider network:
resource "aws_vpc" "ProviderVPC" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "${var.stack_name} Provider VPC"
    }
}

resource "aws_internet_gateway" "EC2InternetGateway" {
    tags = {
        Name = "${var.stack_name}-ProviderIGW"
    }
    vpc_id = aws_vpc.ProviderVPC.id
}
# Note - No gateway attachment in terraform?

resource "aws_subnet" "ProviderSubnet" {
    availability_zone = var.availability_zone
    cidr_block = "10.0.0.0/24"
    vpc_id = aws_vpc.ProviderVPC.id
    map_public_ip_on_launch = true
}

resource "aws_route_table" "ProviderRouteTable" {
    vpc_id = aws_vpc.ProviderVPC.id
    tags = {
        Name = "${var.stack_name} Provider Route table"
    }
}

resource "aws_route" "EC2Route" {
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.EC2InternetGateway.id
    route_table_id = aws_route_table.ProviderRouteTable.id
}

resource "aws_route_table_association" "EC2SubnetRouteTableAssociation" {
    route_table_id = aws_route_table.ProviderRouteTable.id
    subnet_id = aws_subnet.ProviderSubnet.id
}

resource "aws_security_group" "ProviderSecurityGroup" {
    description = "ProviderSecurityGroup"
    name = "${var.stack_name}-ProviderSecurityGroup"
    tags = {
        Name = "${var.stack_name}-ProviderSecurityGroup"
    }
    vpc_id = aws_vpc.ProviderVPC.id
    ingress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 80
        protocol = "tcp"
        to_port = 80
    }
    ingress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = -1
        protocol = "icmp"
        to_port = -1
    }
    egress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 0
        protocol = "-1"
        to_port = 0
    }
}

resource "aws_instance" "ProviderEC2Instance" {
    ami = var.ami_id
    instance_type = "t2.micro"
    subnet_id = aws_subnet.ProviderSubnet.id
    iam_instance_profile = aws_iam_instance_profile.IAMInstanceProfile.name
    vpc_security_group_ids = [
        aws_security_group.ProviderSecurityGroup.id
    ]
    user_data = <<EOT
#!/bin/bash
yum update -y
yum install -y docker
service docker start
docker pull ${var.docker_image}
docker run -d -p80:5000 ${var.docker_image}   
EOT
    tags = {
        Name = "${var.stack_name} Provider Instance"
    }
}



resource "aws_vpc" "ConsumerVPC" {
    cidr_block = "172.16.0.0/16"
    tags = {
        Name = "${var.stack_name} Consumer VPC"
    }
}

resource "aws_internet_gateway" "ConsumerInternetGateway" {
    tags = {
        Name = "${var.stack_name}-ConsumerIGW"
    }
    vpc_id = aws_vpc.ConsumerVPC.id
}

resource "aws_subnet" "ConsumerSubnet" {
    availability_zone = var.availability_zone
    cidr_block = "172.16.0.0/24"
    vpc_id = aws_vpc.ConsumerVPC.id
    map_public_ip_on_launch = true
}

resource "aws_route_table" "ConsumerRouteTable" {
    vpc_id = aws_vpc.ConsumerVPC.id
    tags = {
        Name = "${var.stack_name} Consumer Route table"
    }
}

resource "aws_route" "ConsumerRoute" {
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ConsumerInternetGateway.id
    route_table_id = aws_route_table.ConsumerRouteTable.id
}

resource "aws_route_table_association" "EC2SubnetRouteTableAssociation2" {
    route_table_id = aws_route_table.ConsumerRouteTable.id
    subnet_id = aws_subnet.ConsumerSubnet.id
}

resource "aws_security_group" "ConsumerSecurityGroup" {
    description = "ConsumerSecurityGroup"
    name = "${var.stack_name}-ConsumerSecurityGroup"
    tags = {
        Name = "${var.stack_name}-ConsumerSecurityGroup"
    }
    vpc_id = aws_vpc.ConsumerVPC.id
    ingress {
        cidr_blocks = [
            aws_vpc.ConsumerVPC.cidr_block
        ]
        from_port = 80
        protocol = "tcp"
        to_port = 80
    }
    egress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 0
        protocol = "-1"
        to_port = 0
    }
}

resource "aws_instance" "ConsumerEC2Instance" {
    ami = var.ami_id
    instance_type = "t2.micro"
    subnet_id = aws_subnet.ConsumerSubnet.id
    vpc_security_group_ids = [
        aws_security_group.ConsumerSecurityGroup.id
    ]
    iam_instance_profile = aws_iam_instance_profile.IAMInstanceProfile.name
    tags = {
        Name = "${var.stack_name} Consumer Instance"
    }
}

resource "aws_iam_instance_profile" "IAMInstanceProfile" {
    path = "/"
    name = "${var.stack_name}-SSMInstanceProfile"
    role = aws_iam_role.IAMRole.name
}

resource "aws_iam_role" "IAMRole" {
    path = "/"
    name = "${var.stack_name}-SSMRole"
    assume_role_policy = jsonencode({
        Version = "2008-10-17"
        Statement = [ {
            Effect = "Allow"
            Action = "sts:AssumeRole"
            Principal = { Service = "ec2.amazonaws.com" }
        } ]
    })
    managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"]    
}


# PEERING STARTS HERE!!
resource "aws_vpc_peering_connection" "peering_connection" {
    count       = local.create_peering  # Only create this resource if we want to build a peering demo
    peer_vpc_id = aws_vpc.ProviderVPC.id
    vpc_id      = aws_vpc.ConsumerVPC.id
}  

resource "aws_route" "provider_peering_route" {
    count                     = local.create_peering  # Only create this resource if we want to build a peering demo
    vpc_peering_connection_id = aws_vpc_peering_connection.peering_connection[0].id
    route_table_id            = aws_route_table.ProviderRouteTable.id
    destination_cidr_block    = "172.16.0.0/16"
}

resource "aws_route" "consumer_peering_route" {
    count                     = local.create_peering  # Only create this resource if we want to build a peering demo
    vpc_peering_connection_id = aws_vpc_peering_connection.peering_connection[0].id
    route_table_id            = aws_route_table.ConsumerRouteTable.id
    destination_cidr_block    = "10.0.0.0/16"
}


#  VPC ENDPOINT STARTS HERE
resource "aws_vpc_endpoint_service" "ConsumerEndpointService" {
    count = local.create_private_link  # Only create this resource if we want to build a private link demo
    acceptance_required        = false
    network_load_balancer_arns = [aws_lb.NLB[0].arn]
}

resource "aws_vpc_endpoint" "EC2VPCEndpoint" {
    count = local.create_private_link  # Only create this resource if we want to build a private link demo
    vpc_endpoint_type = "Interface"
    vpc_id = aws_vpc.ConsumerVPC.id
    service_name = "com.amazonaws.vpce.${var.region}.${aws_vpc_endpoint_service.ConsumerEndpointService[0].id}"
    subnet_ids = [ aws_subnet.ConsumerSubnet.id ]
    security_group_ids = [ aws_security_group.ConsumerSecurityGroup.id ]
}

resource "aws_lb" "NLB" {
    count = local.create_private_link  # Only create this resource if we want to build a private link demo
    name = "NetworkLoadBalancer"
    internal = true
    load_balancer_type = "network"
    subnets = [ aws_subnet.ProviderSubnet.id ]
}

resource "aws_lb_target_group" "TG" {
    count = local.create_private_link  # Only create this resource if we want to build a private link demo
    name = "ProviderTargetGroup"
    port = 80
    protocol = "TCP"
    vpc_id = aws_vpc.ProviderVPC.id
    target_type = "instance"
}

resource "aws_lb_target_group_attachment" "attachment" {
    count = local.create_private_link  # Only create this resource if we want to build a private link demo
    target_group_arn = aws_lb_target_group.TG[0].arn
    target_id        = aws_instance.ProviderEC2Instance.id
    port             = 80
}

resource "aws_lb_listener" "Listener" {
    count = local.create_private_link  # Only create this resource if we want to build a private link demo
    load_balancer_arn = aws_lb.NLB[0].arn
    port              = 80
    protocol          = "TCP"
    default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.TG[0].arn
    }
}

# Outputs

output "consumer_session_manager_link" {
    description = "Access the service CONSUMER using web browser." 
    value = "https://${var.region}.console.aws.amazon.com/systems-manager/session-manager/${aws_instance.ConsumerEC2Instance.id}?region=${var.region}#"  
}

output "reachability_analyzer_link" {
    description = "Convenient link to the Network Manager Reachability Analyzer.  Enter 'Consumer' instance as source and 'Provider' instance as target"
    value = "https://${var.region}.console.aws.amazon.com/networkinsights/home?region=${var.region}#CreateNetworkPath"
}

# TODO: CREATE DNS NAME CONDITIONALLY WHEN DOING A VPC ENDPOINT DEMO
# output "dns_name" {
#     count = local.create_private_link  # Only create this resource if we want to build a private link demo
#     description = "DNS Name of the VPC Endpoint."
#     value = element(aws_vpc_endpoint.EC2VPCEndpoint.dns_entry,0)
# }
