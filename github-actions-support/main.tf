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



variable "github_organization" {
  description = "Your GitHub organization name or personal username."
  type        = string
  default     = "kennyk65"
}

variable "github_repository" {
  description = "The name of your GitHub repository."
  type        = string
  default     = "terraform-teaching-demos"
}

variable "aws_account_id" {
  description = "Your 12-digit AWS account ID."
  type        = string
  default     = "011673140073"
}


# variable "application_s3_bucket_name" {
#   description = "Name of the S3 bucket your GitHub Actions role will manage."
#   type        = string
#   default     = "my-app-data-bucket-from-gha" # <<< REPLACE with your application's S3 bucket name
# }

provider "aws" {
}

# --- Data Source for Current Region (used for DDB ARN) ---
data "aws_region" "current" {}


# --- IAM OIDC Identity Provider ---
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = [ "sts.amazonaws.com" ]
  thumbprint_list = [ 
    # Complex process to get this.
    "d89e3bd43d5d909b47a18977aa9d5ce36cee184c" # Github
  ]
  tags = {
    Name = "GitHubActionsOIDCProvider"
  }
}


# --- IAM Role for GitHub Actions ---
resource "aws_iam_role" "github_actions_terraform_role" {
  name = "GitHubActionsTerraformRole" # This name must match your AWS_ROLE_ARN secret in GitHub
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringLike = {
            # This allows any push to any path within your specified GitHub repository to assume the role.
            "${aws_iam_openid_connect_provider.github_actions.url}:sub" = "repo:${var.github_organization}/${var.github_repository}:*"
          },
          StringEquals = {
            "${aws_iam_openid_connect_provider.github_actions.url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
  tags = {
    Name = "GitHubActionsTerraformRole"
  }
}

# --- Policy 1: Permissions for Terraform Backend State Management ---
resource "aws_iam_policy" "terraform_backend_policy" {
  name        = "GitHubActionsTerraformBackendPolicy"
  description = "Policy allowing GitHub Actions role to access the application's Terraform state backend."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::kk-admin-terraform", 
          "arn:aws:s3:::kk-admin-terraform/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ],
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${var.aws_account_id}:table/terraform-lock" 
      }
    ]
  })
  tags = {
    Name = "GitHubActionsTerraformBackendPolicy"
  }
}

# --- Policy 2: Application Resource Deployment Permissions (S3) ---
resource "aws_iam_policy" "application_resource_policy" {
  name        = "GitHubActionsApplicationResourcePolicy"
  description = "Policy allowing GitHub Actions role to manage specific application resources (S3 bucket)."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Allow terraform to create, update, and delete a bucket.
      {
        Effect = "Allow",
        Action = [
          "s3:CreateBucket",      # If your Terraform will create this bucket
          "s3:DeleteBucket",      # If your Terraform will delete this bucket
          "s3:ListBucket"
        ],
        Resource = "*"
      }
      # Add other AWS service permissions here if your 'aws-deploy' Terraform manages
      # resources beyond just this S3 bucket (e.g., EC2, Lambda, RDS, etc.).
    ]
  })
  tags = {
    Name = "GitHubActionsApplicationResourcePolicy"
  }
}

# --- Attach Policies to Role ---
resource "aws_iam_role_policy_attachment" "backend_attachment" {
  role       = aws_iam_role.github_actions_terraform_role.name
  policy_arn = aws_iam_policy.terraform_backend_policy.arn
}

resource "aws_iam_role_policy_attachment" "resource_attachment" {
  role       = aws_iam_role.github_actions_terraform_role.name
  policy_arn = aws_iam_policy.application_resource_policy.arn
}

# --- Outputs ---
output "github_actions_role_arn" {
  description = "The ARN of the IAM role for GitHub Actions to assume."
  value       = aws_iam_role.github_actions_terraform_role.arn
}

output "github_actions_role_name" {
  description = "The name of the IAM role for GitHub Actions to assume."
  value       = aws_iam_role.github_actions_terraform_role.name
}