Terraform **Modules** are containers for multiple resources that are used together. They allow you to package infrastructure into reusable, shareable units—similar to functions in a programming language.

### Core Concepts
* **Root Module:** The directory where you run `terraform apply`.
* **Child Module:** A separate directory (local or remote) called by the root module.
    * Note: it can be above, beside, or below the root module in the file system.
* **State:** Is managed by the Root module.

---

### 1. The Module Directory Structure
A typical child module (e.g., in `./modules/s3-bucket/`) contains:
* `variables.tf`: Defines the **inputs**.
* `main.tf`: Defines the **resources**.
* `outputs.tf`: Defines the **return values**.

---

### 2. Calling a Module (Syntax)
In your root configuration, you call a module using the `module` block.

```hcl
module "app_bucket" {
  source = "./modules/s3-bucket" # Path to the module code. (this example is located below the calling module).

  # --- Inputs ---
  bucket_name = "my-unique-app-data-2026"
  environment = "prod"
}
```

---

### 3. Defining Inputs (Variables)
Inside the child module's `variables.tf`, you define what data the module requires.

```hcl
variable "bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
}

variable "environment" {
  type    = string
  default = "dev"
}
```

---

### 4. Defining Outputs
To pass data *back* to the root module (like a bucket ARN or ID), define an output in the child module's `outputs.tf`.

```hcl
output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "The ARN of the created bucket"
}
```

---

### 5. Accessing Module Outputs
In your root configuration, you reference a module's output using the syntax: `module.<MODULE_NAME>.<OUTPUT_NAME>`.

```hcl
resource "aws_iam_policy" "policy" {
  name   = "my-app-policy"
  # Reference the output from the module above
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "${module.app_bucket.bucket_arn}/*"
    }
  ]
}
EOF
}
```

---

### Pro-Tips for AWS Modules
* **Versioning:** When using remote modules (e.g., from the Terraform Registry or GitHub), always specify a `version` or a specific git tag to avoid breaking changes.
* **Flattening:** Use modules to group resources that share a lifecycle (e.g., a "VPC module" that includes subnets, NAT gateways, and route tables).
* **Naming:** Use generic names inside the module (like `aws_s3_bucket.this`) since the uniqueness comes from the instance name in the root module (`module "app_bucket"`).