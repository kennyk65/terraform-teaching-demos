## Using AWS CodeBuild with Terraform

 This is a common combination when targeting AWS. It replaces your laptop as the execution environment, providing a clean, consistent "runner" for every `plan` and `apply`.

 - It is much less expensive than running an EC2 instance to host Jenkins 24 hours a day.
 - Unlike GitHub Actions, everything can be private to your account.

---
### Example:

This example uses Terraform to establishe a sample CodeBuild project, complete with an IAM Role 
- State Management - A remote backend is *required* as CodeBuild environments are stateless.
- IAM Role - Provides basic permissions to cover basic operations.  It assumes the `.tf` files executing will name their own roles to assume covering permissions needed for specific resources. 

---

### 1. The Terraform Configuration (`codebuild.tf`)

This block creates the CodeBuild Project and the necessary IAM Role. Run this one time:

```hcl
# 1. The CodeBuild Service Role (The "Runner")
resource "aws_iam_role" "codebuild_runner" {
  name = "codebuild-terraform-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}

# 2. Permissions for the Runner itself
resource "aws_iam_role_policy" "codebuild_runner_permissions" {
  role = aws_iam_role.codebuild_runner.name
  name = "codebuild-base-permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # A) CloudWatch Logging
      {
        Action   = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents"]
        Resource = ["*"]
        Effect   = "Allow"
      },
      # B) Remote State Management (S3 + DynamoDB Locking)
      {
        Sid      = "RemoteStateAccess"
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          "arn:aws:s3:::your-terraform-state-bucket",
          "arn:aws:s3:::your-terraform-state-bucket/*",
          "arn:aws:dynamodb:*:*:table/your-lock-table"
        ]
        Effect   = "Allow"
      },
      # C) Allow Terraform itself to assume a separate Role
      {
        Sid      = "AllowProviderAssumeRole"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/terraform-project-*"
        Effect   = "Allow"
      }
    ]
  })
}

# 3. The CodeBuild Project
resource "aws_codebuild_project" "terraform" {
  name         = "terraform-automation"
  service_role = aws_iam_role.codebuild_runner.arn

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type     = "GITHUB"
    location = "https://github.com/your-org/your-repo.git" # Assuming public repo for simplicity.
  }
}
```

---

### The Buildspec (`buildspec.yml`)

Place this file in the root of your infrastructure repository. It defines the "recipe" CodeBuild follows to run Terraform.

```yaml
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.x
    commands:
      - echo "Installing Terraform..."
      - sudo yum install -y yum-utils
      - sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - sudo yum -y install terraform
  pre_build:
    commands:
      - echo "Initializing Terraform..."
      - terraform --version
      - terraform init -input=false
      - echo "Running Terraform Plan..."
      - terraform plan -input=false -out=tfplan
  build:
    commands:
      - echo "Running Terraform Apply using previous plan..."
      - terraform apply -auto-approve -input=false tfplan
```

---

### Notes

* Separate Roles: The Role used by CodeBuild to log and manage state is separate from the Role Terraform uses to build your infrastructure.  This means every stack can have its own least-privilege role.
* State Locking: CodeBuild is stateless.  A Remote Backend is required.  This example assumes S3 + DynamoDB.  CodeBuild Role permissions must cover the permission requirements for state management.
* Environment Variables: Can be passed, but none used in this example.
* Plan vs. Apply: A common best practice is to have two projects:
    * Project Plan: Runs on every Pull Request.
    * Project Apply: Runs only when code is merged into the main branch.
* Image Choice: The `aws/codebuild/amazonlinux2-x86_64-standard:5.0` image comes with many tools pre-installed, but not Terraform.  The install phase spends several seconds on **each** build to install Terraform.  CodeBuild charges according to build time.  For faster, less expensive builds, create a custom Docker image that has Terraform already installed.
