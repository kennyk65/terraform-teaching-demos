# GitLab CI/CD with Terraform (AWS)

## Overview

This guide demonstrates how to use **GitLab CI/CD pipelines** to provision infrastructure in **Amazon Web Services (AWS)** using **Terraform**.

Key ideas:

* Pipelines are defined in `.gitlab-ci.yml`
* Pipelines run automatically on commits and merge requests
* Authentication is handled via CI/CD variables
* Terraform commands are executed inside pipeline jobs
* Infrastructure changes follow a **plan → review → apply** workflow

---

## Prerequisites

* GitLab account and repository
* AWS account
* Terraform configuration files (`.tf`)
* Basic familiarity with Git

---

## Repository Structure

```plaintext
.
├── main.tf
├── variables.tf
├── outputs.tf
└── .gitlab-ci.yml
```

---

## Step 1 – Configure AWS Credentials

In your GitLab project:

**Settings → CI/CD → Variables**

Add the following variables:

```plaintext
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION
```

Recommended settings:

* Mark as **Masked**
* Mark as **Protected** (for main branch)

Terraform will automatically use these during execution.

---

## Step 2 – Create the Pipeline Configuration

Create a file named:

```plaintext
.gitlab-ci.yml
```

---

## Step 3 – Define Pipeline Stages

```yaml
stages:
  - validate
  - plan
  - apply
```

---

## Step 4 – Configure Terraform Jobs

```yaml
image: hashicorp/terraform:light

variables:
  TF_ROOT: .
  AWS_DEFAULT_REGION: us-east-1

before_script:
  - cd $TF_ROOT

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

---

## Step 5 – Commit and Run Pipeline

```bash
git add .
git commit -m "Add GitLab CI pipeline"
git push
```

This will:

1. Trigger pipeline execution
2. Run `terraform validate`
3. Generate a `terraform plan`
4. Store the plan as an artifact

---

## Step 6 – Review Plan Output

* Navigate to **CI/CD → Pipelines**
* Open the latest pipeline
* View logs from the `plan` job

Use this output to verify infrastructure changes before applying.

---

## Step 7 – Apply Changes

* Go to the pipeline
* Locate the `apply` job
* Click **Run**

This executes:

```bash
terraform apply tfplan
```

---

## Step 8 – Terraform State Management

You should use a **remote backend** for state.

### Option A – GitLab Managed State

```hcl
terraform {
  backend "http" {}
}
```

GitLab provides:

* Secure state storage
* State locking
* Versioning

---

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

---

## Step 9 – Pipeline Behavior

### Automatic Execution

Pipelines run on:

* Code push
* Merge request creation
* Branch updates

---

### Restrict Apply to Main Branch

```yaml
apply:
  only:
    - main
```

---

### Manual Approval

```yaml
apply:
  when: manual
```

Prevents unintended infrastructure changes.

---

## Step 10 – Passing Plan Between Stages

```yaml
plan:
  artifacts:
    paths:
      - tfplan
```

This ensures:

* The exact plan reviewed is applied
* No re-computation between stages

---

## Step 11 – Caching Terraform Dependencies

```yaml
cache:
  paths:
    - .terraform/
```

Improves performance by avoiding repeated downloads.

---

## Step 12 – Environment Separation

### Directory-Based

```plaintext
envs/
  dev/
  prod/
```

---

### Branch-Based

* `main` → production
* `develop` → development

---

## Step 13 – Security Best Practices

* Store secrets only in CI/CD variables
* Use protected branches for production
* Avoid exposing sensitive output in logs
* Limit access to pipeline execution

---

## Step 14 – Optional: Use GitLab Terraform Helper

GitLab provides a wrapper:

```bash
gitlab-terraform init
gitlab-terraform plan
gitlab-terraform apply
```

This simplifies:

* State configuration
* CI/CD integration

---

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
