### Terragrunt Overview
**Terragrunt** is a thin wrapper for Terraform that provides extra tools for keeping your configurations **DRY** (Don't Repeat Yourself), managing multiple modules, and handling remote state automatically.

---

### Core Problems Terragrunt Solves

* **Remote State Bloat:** Instead of copy-pasting the `backend` block into every module, you define it once in a root file.
* **Provider Redundancy:** Define your `provider "aws"` block once and "generate" it into all child modules.
* **Command Complexity:** Replaces long CLI commands (like `-var-file="prod.tfvars"`) with simple folder-based execution.
* **Dependency Management:** Allows you to define that Module B must wait for Module A to finish.

---

### 1. The Directory Structure
Terragrunt encourages a directory-per-environment structure.

```text
.
├── terragrunt.hcl          # Root config (Remote State & Providers)
├── dev
│   └── vpc
│       └── terragrunt.hcl  # Child config (Inputs for VPC)
└── prod
    └── vpc
        └── terragrunt.hcl  # Child config (Inputs for VPC)
```

---

### 2. The Root `terragrunt.hcl`
This file typically handles the "Global" settings like where the state is stored.

```hcl
# Auto-generate the backend configuration for all sub-modules
remote_state {
  backend = "s3"
  config = {
    bucket         = "my-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "my-lock-table"
  }
}

# Auto-generate the provider file
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
}
EOF
}
```

---

### 3. The Child `terragrunt.hcl`
Inside an environment folder (e.g., `prod/vpc`), you point to the actual Terraform source and provide the variables.

```hcl
# Pull in the root settings (backend/providers)
include "root" {
  path = find_in_parent_folders()
}

# Point to the actual Terraform code (Local or Git)
terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=5.0.0"
}

# Define the environment-specific values
inputs = {
  name = "prod-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b"]
}
```

---

### 4. Common Commands

| Command | Description |
| :--- | :--- |
| `terragrunt plan` | Runs `terraform plan` for the current folder. |
| `terragrunt apply` | Runs `terraform apply` for the current folder. |
| `terragrunt run-all plan` | Recursively plans **every** module in the directory tree. |
| `terragrunt output` | Views outputs for the specific module. |

---

### Why use this for your AWS course?
If you find yourself manually managing `.tfvars` files and constantly worrying about running the wrong command in the wrong account, Terragrunt acts as a "safety rail." It forces the environment values to be tied to the folder path, effectively eliminating the risk of accidental cross-environment deployments.