
# GitLab CI/CD with Terraform (AWS)

## Overview

This guide demonstrates how to use **GitLab CI/CD pipelines** to provision infrastructure in **Amazon Web Services (AWS)** using **Terraform**.

Key ideas:

* Pipelines are defined in `.gitlab-ci.yml`
* Pipelines run automatically on commits and merge requests
* Authentication uses **OIDC + IAM role (no stored credentials)**
* Terraform commands are executed inside pipeline jobs
* Infrastructure changes follow a **plan → review → apply** workflow


## Prerequisites

* GitLab account and repository
* AWS account
* Terraform configuration files (`.tf`)
* Basic familiarity with Git


## Repository Structure

```plaintext
.
├── main.tf
├── variables.tf
├── outputs.tf
└── .gitlab-ci.yml
```



## Step 1 – Configure AWS Authentication (OIDC + IAM Role)

### Overview

Use GitLab’s OIDC integration to assume an AWS IAM role at runtime.
No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` are stored.



### Step 1A – Create IAM Role in AWS

Create an IAM role with a trust policy allowing GitLab to assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:sub": "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

Attach appropriate permissions for Terraform (e.g., EC2, S3, etc.).



### Step 1B – Add CI/CD Variable

In GitLab:

**Settings → CI/CD → Variables**

Add:

```plaintext
AWS_ROLE_ARN
```

Example:

```plaintext
arn:aws:iam::123456789012:role/gitlab-terraform-role
```

Mark as:

* **Protected**
* **Masked** (optional)



### Step 1C – Configure OIDC in Pipeline

Add to `.gitlab-ci.yml`:

```yaml
id_tokens:
  AWS_ID_TOKEN:
    aud: https://gitlab.com
```



### Step 1D – Export Token for AWS

In the pipeline:

```yaml
before_script:
  - echo "$AWS_ID_TOKEN" > /tmp/aws_token
  - export AWS_WEB_IDENTITY_TOKEN_FILE=/tmp/aws_token
  - export AWS_ROLE_ARN=$AWS_ROLE_ARN
```



### Step 1E – Terraform AWS Provider

```hcl
provider "aws" {
  region = var.region
}
```

Terraform will automatically use:

* `AWS_ROLE_ARN`
* `AWS_WEB_IDENTITY_TOKEN_FILE`



## Step 2 – Create the Pipeline Configuration

Create:

```plaintext
.gitlab-ci.yml
```



## Step 3 – Define Pipeline Stages

```yaml
stages:
  - validate
  - plan
  - apply
```



## Step 4 – Configure Terraform Jobs

```yaml
image: hashicorp/terraform:light

stages:
  - validate
  - plan
  - apply

variables:
  TF_ROOT: .
  AWS_DEFAULT_REGION: us-east-1

id_tokens:
  AWS_ID_TOKEN:
    aud: https://gitlab.com

before_script:
  - cd $TF_ROOT
  - echo "$AWS_ID_TOKEN" > /tmp/aws_token
  - export AWS_WEB_IDENTITY_TOKEN_FILE=/tmp/aws_token
  - export AWS_ROLE_ARN=$AWS_ROLE_ARN

validate:
  stage: validate
  script:
    - terraform init
    - terraform validate

plan:
  stage: plan
  script:
    - terraform init
    - terraform plan -out=tfplan
  artifacts:
    paths:
      - tfplan

apply:
  stage: apply
  script:
    - terraform apply tfplan
  when: manual
  only:
    - main
```



## Step 5 – Commit and Run Pipeline

```bash
git add .
git commit -m "Add GitLab CI pipeline"
git push
```

Pipeline will:

1. Authenticate via OIDC
2. Assume IAM role
3. Run `terraform validate`
4. Generate `terraform plan`



## Step 6 – Review Plan Output

* Navigate to **CI/CD → Pipelines**
* Open pipeline
* Inspect `plan` job logs



## Step 7 – Apply Changes

* Open pipeline
* Run `apply` job manually

```bash
terraform apply tfplan
```



## Step 8 – Terraform State Management

### Option A – GitLab Managed State

```hcl
terraform {
  backend "http" {}
}
```



### Option B – AWS S3 Backend

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```



## Step 9 – Pipeline Behavior

### Automatic Execution

* Push
* Merge request
* Branch updates



### Restrict Apply to Main

```yaml
apply:
  only:
    - main
```



### Manual Approval

```yaml
apply:
  when: manual
```



## Step 10 – Passing Plan Between Stages

```yaml
plan:
  artifacts:
    paths:
      - tfplan
```



## Step 11 – Cache Terraform Dependencies

```yaml
cache:
  paths:
    - .terraform/
```



## Step 12 – Environment Separation

### Directory-Based

```plaintext
envs/
  dev/
  prod/
```



### Branch-Based

* `main` → production
* `develop` → development



## Step 13 – Security Best Practices

* Use OIDC (no long-lived credentials)
* Restrict IAM trust policy to specific branches
* Use protected branches
* Limit who can trigger pipelines



## Step 14 – Optional Terraform Helper

```bash
gitlab-terraform init
gitlab-terraform plan
gitlab-terraform apply
```



## Summary

Typical workflow:

```plaintext
Commit → Pipeline runs validate/plan → Review output → Manually apply
```

This approach provides:

* Automated validation
* Controlled infrastructure changes
* Repeatable deployments
* Integration with GitLab CI/CD pipelines

