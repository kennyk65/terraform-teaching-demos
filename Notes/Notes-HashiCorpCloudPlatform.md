## IBM HCP Terraform
#### IBM HashiCorp Cloud Platform Terraform


>The Name
>*   *HashiCorp bought by IBM in 2025*
>*   *Formerly HCP Terraform, since 2023*
>*   *Formerly Terraform Cloud, since 2019*
>*   *Formerly terraform Pro / Premium, earlier*
>
>Also:
>* *Terraform Enterprise* is the name of the installed, self-hosted variant.


HCP Terraform is a managed SaaS "control plane" that moves execution from your local machine to remote, standardized runners.

### 1. State Management
* **Automatic Handling:** Replaces local and remote backends.  Uses built-in, encrypted storage.
* **Native Locking:** Prevents "state-file corruption" automatically; no files or external DB required.
* **Version History:** Visual UI to compare every state change, showing exactly which user added/removed which resource.

### 2. Workspaces - Major Terminology Shift.
* **Unified Container:** Unlike CLI workspaces (which are just separated state files), an HCP **Workspace** bundles:
    * state
    * variables
    * run history
    * VCS (GitHub/GitLab) connections
* **Variable Sets:** Define variables in a web dashboard rather than maintaining dozens of .tfvars files.
* **Environment Isolation:** Each environment has a unique URL and specific access controls, reducing the risk of accidental "dev-to-prod" deployments.

### 3. Secrets & Security
* **Sensitive Variables:** Mark variables as "Sensitive" to make them **write-only**. They are hidden from the UI/API and only decrypted during the run.
* **Remote Execution:** Since `plan` and `apply` happen in the cloud, sensitive values never touch your local disk or logs.
* **Vault Integration:** Supports dynamic, short-lived credentials via HashiCorp Vault.


---

### Basic Pricing Info (Estimated 2026)

HCP Terraform primarily scales based on **Resources Under Management (RUM)**.

* **Free Tier:**
    * **Cost:** **$0**
    * **Limits:** Up to **500 resources**. Includes VCS integration, state management, and basic remote runs.
* **Standard Tier:**
    * **Cost:** Pay-as-you-go (approx. **$0.00014 per resource/hour**).
    * **Features:** Unlimited resources, concurrent runs, and "drift detection."
* **Plus / Enterprise:**
    * **Cost:** Custom/Contract pricing.
    * **Features:** Policy-as-Code (Sentinel), audit logs, and self-hosted agents for private networks.

> **Note:** For a solo instructor or small team, the **Free Tier** is usually more than enough until you exceed the 500-resource threshold.