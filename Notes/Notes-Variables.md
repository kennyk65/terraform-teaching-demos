## Variables

Terraform variables allow you to de-couple your infrastructure configuration from environment-specific values, making your code reusable and portable.

## 1. Defining Variables

Variables are defined in .tf files.  Use `main.tf`.  For larger # of variables it is common to use `variables.tf`

Example: This defines a variable specifying an EC2 instance type.
```
variable "instance_size" {
  type        = string
  description = "The EC2 instance type"
  default     = "t3.micro" # Optional: provides a fallback value

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_size)
    error_message = "Only burstable t3 instances are allowed."
  }
}
```


| Attribute | Required? | Default / Behavior | Purpose |
| :--- | :--- | :--- | :--- |
| **`type`** | Optional | `any` | Constrains the data type (e.g., `string`, `number`, `bool`, `list`, `map`, `object`). Inferred from default if missing |
| **`default`** | Optional | `null` | The value used if no input is provided via CLI, `.tfvars`, or environment variables. Must be literal constant, can't reference another variable |
| **`description`** | Optional | `null` | Documentation string. Displayed in `terraform plan`  |
| **`validation`** | Optional | None | A block used to define custom rules (via `condition` and `error_message`) for input values. |
| **`sensitive`** | Optional | `false` | If `true`, Terraform masks the value in CLI output (logs/plan) to protect secrets. Does NOT mask this in state storage |
| **`nullable`** | Optional | `true` | If `false`, the variable cannot be set to `null` even if a default is provided. |

---

#### 2. `validation` Blocks
You can have multiple validation blocks for a single variable. 

This validation block restricts the instance count to 1 to 10:
```
variable "instance_count" {
  type        = number
  description = "Number of instances to deploy"

  validation {
    condition     = var.instance_count > 0 && var.instance_count <= 10
    error_message = "The instance_count must be between 1 and 10."
  }
}
```

This validation rule requires that the bucket name start with the letters "dev-"
```hcl
variable "bucket_name" {
  type    = string
  default = "dev-app-data"

  validation {
    condition     = can(regex("^dev-", var.bucket_name))
    error_message = "The bucket name must start with 'dev-'."
  }
}
```

### 3. Populating Variables & Order of Precedence

**Precedence** If a value is defined in multiple places, Terraform follows this Order of Precedence (highest number wins):

1. Environment variables (TF_VAR_name) — Lowest Priority
2. The terraform.tfvars file
3. The terraform.tfvars.json file
4. Any *.auto.tfvars or *.auto.tfvars.json files (processed in lexical order)
5. Any -var and -var-file options on the command line — Highest Priority

**Missing value** If a variable has no value, no default, and is not nullable,  `terraform apply` will prompt you for a value.  Input prompting can be suppressed with `-input=false` - which would result in an error. 


### 4. Workspace-Based Variable Loading
**Terraform CANNOT** load different variable values based on the selected workspace (big miss).

It's common to use `locals{}` instead in this case

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
```
```
resource "aws_instance" "web" {
  count         = local.config.instance_count
  instance_type = local.config.instance_type
  # ...
}
```

Dynamically selecting values based on workspace selection, larger # of values in external YAML file (not tfvars):
```
locals {
  # Construct path dynamically. ${path.module} is the path of current HCL file.
  # This example assumes we store yaml files for each workspace in a `vars` subfolder.
  vars_file = "${path.module}/vars/${terraform.workspace}.yaml"
  
  # Load and decode the file content
  # We use try() to handle cases where a workspace file might be missing
  env_vars = yamldecode(file(local.vars_file))
}
```
```
output "database_name" {
  value = local.env_vars.db_name
}
```
> Note: this is NOT using tfvars to hold the values.


