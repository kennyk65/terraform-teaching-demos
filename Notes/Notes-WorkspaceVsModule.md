
# Terraform Architecture: Workspaces vs. Directory-Based Modules

This guide outlines the pros, cons, and best practices for managing multiple environments (Dev, Staging, Prod) in Terraform.

---

## 1. Terraform Workspaces
Workspaces allow you to manage multiple state files from a single configuration directory using the same code.

### How it Works
* **State Isolation:** Terraform creates separate state files (e.g., `terraform.tfstate.d/dev/`).
* **Variable Handling:** 2 ways: either manual `-var-file` flags or `terraform.workspace` map lookups in your HCL code.

Manually selecting a set of variable values (not recommended):
```
terraform workspace select prod` -> `terraform apply -var-file="prod.tfvars"
```

Dynamically selecting values based on workspace selection, small # of values:
```
locals {
  env_settings = {
    default = {
      instance_count = 1
      instance_type  = "t3.micro"
    }
    staging = {
      instance_count = 2
      instance_type  = "t3.small"
    }
    production = {
      instance_count = 5
      instance_type  = "m5.large"
    }
  }

  # Select the configuration based on the current workspace
  # Fallback to 'default' if the workspace isn't explicitly defined
  config = lookup(local.env_settings, terraform.workspace, local.env_settings["default"])
}

------------

resource "aws_instance" "web" {
  count         = local.config.instance_count
  instance_type = local.config.instance_type
  # ...
}
```

Dynamically selecting values based on workspace selection, larger # of values:
```
locals {
  # Construct the file path dynamically. ${path.module} is the path of current HCL file.
  # This example assumes we store yaml files for each workspace in a `vars` subfolder.
  vars_file = "${path.module}/vars/${terraform.workspace}.yaml"
  
  # Load and decode the file content
  # We use try() to handle cases where a workspace file might be missing
  env_vars = yamldecode(file(local.vars_file))
}

output "database_name" {
  value = local.env_vars.db_name
}
```


### Disadvantages
* **Implicit Context:** Your current "context" is obscure in the CLI state. It is not always obvious which environment you are about to modify.
* **Variable Mismatch:** Highly prone to human error if relying on setting the `-var-file`.
* **Shared Logic:** All environments share the exact same code, this forces you to make a lot of conditional logic for different environments.

---

## 2. Directory-Based Modules (Best Practice)
This approach treats your infrastructure as a **Reusable Module**, which is then called by unique "root" configurations in separate directories.

### How it Works
* **Structure:** 
    * `/modules/app-stack`: Contains the core logic.
    * `/envs/dev/main.tf`: Calls the module with Dev-specific variables.
    * `/envs/prod/main.tf`: Calls the module with Prod-specific variables.
* **State Isolation:** Each environment has a physically separate backend configuration.

### The Advantages
* **"Sticky" Variables:** Variables are hard-coded into the module call within each directory. You simply run `terraform apply`.  No need for extra CLI flags or `locals` map lookups.
* **Blast Radius Reduction:** A corruption or accidental deletion of the Dev state file has zero physical path to the Prod state file.
* **Credential Isolation:** You can easily map different IAM roles or service accounts to specific directories, preventing cross-environment accidents.
* **Version Control:** You can point Dev to a "feature branch" of a module while keeping Prod pinned to a "stable" tag.

ALSO - Modules can be published to repositories, and referenced by their version number.  This allows the prod stack to use v 1.0 of a module while dev uses a local module, or v2.

---

## Comparison Summary

| Feature | Terraform Workspaces | Directory-Based Modules |
| :--- | :--- | :--- |
| **Best For** | Ephemeral/Short-lived testing | Long-lived Production environments |
| **Variable Safety** | **Low:** Relies on memory/CLI flags | **High:** Defined in the directory's code |
| **State Security** | Often shared backend access | Fully isolated backends |
| **Code Promotion** | All envs move at once | Staged (Dev -> Stage -> Prod) |
| **Visibility** | Hidden in CLI state | Explicit in file structure |

---

## Final Recommendation

**Avoid Workspaces for Production.** 
While workspaces are excellent for testing a specific Pull Request or feature branch, they lack the guardrails required for stable infrastructure. 

**Use Directory-Based Modules** for your permanent environments. The slight increase in initial boilerplate is a small price to pay for the physical isolation and explicit configuration it provides.

```