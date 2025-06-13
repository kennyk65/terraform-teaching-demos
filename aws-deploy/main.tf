
#  This is a simple configuration file of minimal complexity (except the backend state management).
#  Its purpose is to demonstrate running Terraform within a GitHub action.


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80.0, < 6.0.0" # Not tested beyond v5.
    }
  }
  backend "s3" {
    bucket         = "kk-admin-terraform"
    key            = "aws-deploy/default/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}


provider "aws" {
    region = "us-west-2"
}

# create an s3 bucket 
resource "aws_s3_bucket" "temp-bucket" {
    bucket = "kk-testing-github-action"
}
