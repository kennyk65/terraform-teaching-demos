## AWS Role Assumption in Terraform

Terraform uses the AWS SDK to create, modify, and delete AWS resources.  The SDK requires AWS credentials in order to make the API calls.  

There are safe - and not so safe - ways to provide these credentials to Terraform.  

**The safest option is to have Terraform assume an IAM Role** when it processes your template.  Role assumption produces temporary credentials (hours), and can be associated with policies limited to the bare-minimum needed for the task at hand (grant least privilege).  

These notes explain how to have Terraform assume an IAM Role. 

### 1. The AWS Credential Search Order
The AWS Go SDK (used by Terraform) follows a specific "Chain of Provider" to find your **initial identity**. It stops at the first one it finds:

1.  **Environment Variables:** `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. (Used for "elsewhere" / local dev).
2.  **Shared Credentials File:** `~/.aws/credentials`.
3.  **Instance Metadata Service (IMDS):** Automatically used when running on an **EC2 instance** with an attached IAM Role.



---

### 2. The "Pivoting" Strategy: Why use Roles?
Hard-coding high-privilege credentials is a critical security failure. Instead, we use a **Pivot Strategy**:

* **On EC2/CodeBuild:** The runner has an Instance Profile with **zero** infrastructure permissions. Its only permission is `sts:AssumeRole`.
* **Elsewhere (Local/SaaS):** You use an Access Key/Secret Key (AK/SK) that is similarly restricted. It can do nothing *except* assume the designated project role.
* **Benefits:** This creates a "Blast Radius" barrier. If your AK/SK is leaked, the attacker still needs to know which Role ARN to assume to do any damage.

---

### 3. Implementation in HCL
This configuration avoids hard-coding the region or the ARN, allowing the same code to be reused across different environments.

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "target_role_arn" {
  type        = string
  description = "The ARN of the IAM role to assume"
  # Provide a default for the primary project role
  default     = "arn:aws:iam::123456789012:role/terraform-project-default"
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = var.target_role_arn
    session_name = "TerraformExecutionSession"
  }
}

# Example resource
resource "aws_s3_bucket" "state_storage" {
  bucket = "company-terraform-state-${var.aws_region}"
}
```

---

### 4. Caveat: Credentials are needed to assume an IAM Role

**The catch:**  The `sts:assumeRole` call itself is an AWS API call, requiring credentials and permissions.  Therefore, one must provide an initial set of credentials to Terraform to allow the assumeRole to work.

- **Running Terraform on EC2?**: 
    -   If running Terraform on EC2, Assign a role to the EC2 instance.  
        -   The EC2 instance will automatically assume it on startup.  
        -   Temporary credentials are automatically made available to the SDKs (and Terraform) via an internal instance metadata endpoint.  
        -   Terraform can then use the credentials and permissions provided by this role to assume *another* role.
        -   This is a highly secure option.

- Off EC2: If running Terraform on a local computer, long term credentials are needed.
    - Option 1: The new `aws login`: The most modern flow (AWS CLI v2.32.0+). It uses a browser-based handshake to retrieve temporary credentials directly into your current session.
    - Option 2: `aws sso login` (with `aws configure sso`): The standard flow for organizations using *IAM Identity Center*. It creates a managed profile in your ~/.aws/config and handles the rotation of temporary tokens for you.
    - Option 3: Permanent Credentials (~/.aws/credentials): The legacy approach using a hard-coded Access Key and Secret Key for a specific IAM User.
    - **The Authorization Requirement**: Regardless of which of the three option is used to authenticate, the identity must have an IAM policy that allows the `sts:AssumeRole` action. No other permissions are needed since Terraform will use this to assume *another* role.
    
- **Running on IBM HCP Terraform?**:
-   HashiCorp Platform Terraform (i.e. Terraform cloud) uses OIDC / Identity Federation to assume an IAM Role.
    -   You create a Trust Relationship between an AWS IAM Role and the HCP Terraform OIDC provider. 
    -   When a run starts, HCP Terraform generates a temporary JWT (JSON Web Token), which AWS exchanges for a short-lived IAM session. 
    -   This provides the credentials / permissions to allow Terraform to assume *another* role.
    -   This is a highly secure option.


---

### 5. Summary: Security Posture
* **Hard-coded Credentials = Bad:** Never store long-term "Admin" keys. They are difficult to rotate and easy to leak.
* **The "Assume" Requirement:** Whether running on an EC2 (via Instance Profile) or elsewhere (via limited AK/SK), the base identity should have **no direct permissions** to create resources. 
* **Identity vs. Permission:** Your base identity (AK/SK or Instance Role) proves **who you are**. The `assume_role` block defines **what you are allowed to do**.
* **Dynamic Configuration:** By using variables for `region` and `role_arn`, you ensure the configuration remains portable and environment-agnostic.