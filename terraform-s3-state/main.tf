
# This configuration establishes AWS resources necessary to support terraform remote state management.
# It creates an S3 bucket with versioning and a lifecycle policy, and a DynamoDB table for locking.
# Other configurations can use this shared state by using the following configuration:
#
# terraform {
#   backend "s3" {
#     bucket         = "kk-admin-terraform"
#     key            = "YOUR-MODULE/YOUR-WORKSPACE/terraform.tfstate"
#     region         = "us-west-2"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }



terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 5.80.0, < 6.0.0"    # Not tested beyond v5.
    }
  }
}

provider "aws" {
  region = "us-west-2"  # Hard coded intentionally
}

# S3 bucket dedicated for storing Terraform state files.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "kk-admin-terraform"
  tags = {
    Name        = "Terraform State Bucket"
    Environment = "Universal"
  }
}

# S3 bucket versioning is recommended for terraform state files.
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# For personal use, there is no need to store old versions.
# Delete non-current versions after 30 days:
resource "aws_s3_bucket_lifecycle_configuration" "cleanup_old_versions" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    id     = "delete-noncurrent-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}


# Terraform's remote state management requires a DDB table for locking: 
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Name        = "Terraform Lock Table"
    Environment = "Universal"
  }
}
