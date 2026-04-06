## OIDC/GitHub Actions Terraform Flow 

Note that the code here involves two separate folders/repositories:
* An **IAMBootstrap** repository to establish the OIDC connect provider and IAM role.
* A **Infrastructure** repository, containing any `

1. **Setup GitHub Actions & Terraform to work with IAM Roles.**  
    * Create this file in the **IAMBootstrap** repository.  
        * It establishes GitHub as an OIDC provider in your AWS Account.  
    * Run this once.  
    * Run it outside of GitHub actions (because it is used to setup GitHub actions).  
    * Specify the **Infrastructure** repository name as the `repo_name` value:

    `bootstrap-terraform-oidc.tf` (Run ONCE)
    ```
    variable "repo_org" { type = string }
    variable "repo_name" { type = string }
    variable "repo_branch" { type = string }

    # Establish GitHub as an OIDC Provider in your AWS account:
    resource "aws_iam_openid_connect_provider" "github" {
    url = "https://token.actions.githubusercontent.com"
    client_id_list  = ["sts.amazonaws.com"]
    thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]  # GitHub cert.  Use this exact value.
    }

    # Create a trust policy for the Role (defined below).  This allows GitHub Actions to assume the role, but only if associated with a specific repository / branch (see variables above, must be set):
    data "aws_iam_policy_document" "trust" {
    statement {
        actions = ["sts:AssumeRoleWithWebIdentity"]
        principals {
        type        = "Federated"
        identifiers = [aws_iam_openid_connect_provider.github.arn]
        }
        condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
        }
        condition {
        test     = "StringLike"
        variable = "token.actions.githubusercontent.com:sub"
        values   = ["repo:${var.repo_org}/${var.repo_name}:ref:refs/heads/${var.repo_branch}"]
        }
    }
    }

    # Create the Role to be assumed by GitHub Actions. Note that specific policies will need to be attached (not included here)
    resource "aws_iam_role" "terraform" {
    name               = "GitHubTerraform"
    assume_role_policy = data.aws_iam_policy_document.trust.json
    # Attach specific policies here.
    }

    # The resulting Role ARN must be used below:
    output "role_arn" { value = aws_iam_role.terraform.arn }
    ```
    Also establish a tfvars file to provide variable values:
    `terraform.tfvars`
    ```
    repo_org = "kenkrueger"
    repo_name = "my-infrastructure"  
    repo_branch = "main"
    ```

1. Deploy this stack
    
    - Run Terraform:
    ```
    $ terraform apply
    ```

    - Or, override variable values if you like:
    ```
    $ terraform apply -var="repo_org=YOURORG" -var="repo_name=myrepo" -var="repo_branch=main"
    ```
    - Record the vlaue of the Role ARN, it is needed in the next step.
    

1. Setup Role ARN and target Region in GitHub:
    * Copy output from the previous step, i.e. `role_arn = arn:aws:iam::123456789012:role/GitHubTerraform`
    * Go to the **Infrastructure** repository where you will be running your GitHub Actions.  *→ Settings → Secrets and variables → Actions*
    * Save a new repository secret (adjust this value):
        ```
        Name:  AWS_ROLE_ARN
        Value: arn:aws:iam::123456789012:role/GitHubTerraform
        ```
    * Save a new repository variable (adjust this value):
        ```
        Name:  AWS_REGION
        Value: us-west-2
        ```

1. Adjust GitHub Repo Settings
    * *Settings → Actions → General → 
✅ "Read and write permissions"*

1. *GitHub Actions.*  This is a sample GitHub Action.  It is triggered when a push is made to the main branch of the **Infrastructure** repository, or when a pull request is created:

    `.github/workflows/terraform.yml`
    ```
    name: Deploy Infrastructure
    on:
    push:
        branches: [main]
    pull_request:

    permissions:
    id-token: write      # REQUIRED for OIDC
    contents: read

    jobs:
    deploy:
        runs-on: ubuntu-latest
        steps:
        - name: Checkout code
        uses: actions/checkout@v4
        
        - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
            role-arn: ${{ secrets.AWS_ROLE_ARN }}  # Use repo secret, no hard-coding
            aws-region: ${{ vars.AWS_REGION }}     # Use repo variable, no hard-coding
        
        - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
            terraform_version: 1.14.8
        
        - name: Terraform Init
        run: terraform init
        
        - name: Terraform Format
        run: terraform fmt -check
        
        - name: Terraform Plan
        run: terraform plan
        
        - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
    ```

1. Your **Infrastructure** repository will contain normal `*.tf` files.  Allow GitHub Actions to dynamically supply the region code rather than hard-coding:

    `main.tf` 

    ```
    # This variable will be set by the GitHub Action
    variable "aws_region" { type = string }

    provider "aws" {
    region = var.aws_region  # Dynamic via CI/CD
    }
    ```

1. Use
    - The GitHub Action will execute every time there is a commit to the main branch of your repository.  It will automatically apply changes to your account.
    ```
