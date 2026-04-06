# Using Terraform to conditionally create resources.

In Terraform, you do this using the **`count`** meta-argument or the **`for_each`** meta-argument. 


---

## 1. Using `count` for Conditional Logic
The `count` argument determines how many instances of a resource to create. A conditional expression (ternary operator) can be used to set `count` to either `1` (create) or `0` (don't).

### The Syntax
$count = condition ? true\_value : false\_value$

### The Implementation
```hcl
variable "env" {
  type    = string
  default = "dev"
}

resource "aws_subnet" "extra_prod_subnet" {
  count = var.env == "prod" ? 1 : 0

  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.100.0/24"
  ...
}
```


---

## 2. Using `for_each` for Dynamic Sets
To create *multiple* subnets based on a list defined in your variables, use `for_each`. It is more flexible because it handles maps and sets, like the IP addresses shown here.

```hcl
locals {
  is_prod = terraform.workspace == "prod"

  # Define the "Schema" for your subnets
  subnet_config = local.is_prod ? {
    "frontend" = {
      cidr   = "10.0.1.0/24"
      public = true
      az     = "us-east-1a"
    }
    "backend" = {
      cidr   = "10.0.2.0/24"
      public = false
      az     = "us-east-1b"
    }
  } : {} # Empty map for non-prod
}

resource "aws_subnet" "dynamic_subnets" {
  for_each = local.subnet_config

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = each.value.public
  availability_zone       = each.value.az

  tags = {
    Name = each.key # Uses "frontend" or "backend"
  }
}
```

---

## Important Nuances

### Referencing Resources with `count`
When you use `count`, the resource becomes a **list** with 0 or 1 entries. You cannot reference it as `aws_subnet.extra_prod_subnet.id`. You must use index notation or a splat:
* **Specific index:** `aws_subnet.extra_prod_subnet[0].id` (Note: This will error if count is 0!)
* **Splat (safely gets all values, or empty list):** `aws_subnet.extra_prod_subnet.*.id`
* **One/None pattern:** `try(aws_subnet.extra_prod_subnet[0].id, null)`


### Referencing Resources with `for_each`
When you use `for_each`, the resource becomes a **Map** (indexed by your keys). You cannot reference it as `aws_subnet.example.id`.

* **Specific Key:** `aws_subnet.example["subnet_a"].id`
    *(Note: This will error if the key "subnet_a" is missing from the map!)*
* **Values Splat (safely gets all values):** `values(aws_subnet.example)[*].id`
    *(Returns a list of IDs; returns an empty list `[]` if the map is empty.)*
* **The `one()` pattern:** `one(values(aws_subnet.example)[*].id)`
    *(Returns the ID if there is exactly one resource; returns `null` if the map is empty.)*
* **Attribute Map:** `{ for k, s in aws_subnet.example : k => s.id }`
    *(Creates a lookup map of `name => id` for use in other resources.)*



### Data Sources
You can also use this logic with **Data Blocks**. In this example we want to use a 'hardened' AMI in production, but an off-the-shelf Ubuntu in dev:
```hcl
locals {
  is_prod = terraform.workspace == "prod"
}

# 1. This search ONLY runs in Production
data "aws_ami" "hardened_prod_image" {
  count       = local.is_prod ? 1 : 0
  most_recent = true
  owners      = ["123456789012"] # Your Corporate Security Account

  filter {
    name   = "name"
    values = ["hardened-prod-linux-*"]
  }
}

# 2. This search ALWAYS runs (our fallback)
data "aws_ami" "standard_ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's Official Account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
```
```
resource "aws_instance" "web_server" {
  # Logic: Use the hardened image if it exists; otherwise, use standard Ubuntu.
  ami = try(data.aws_ami.hardened_prod_image[0].id, data.aws_ami.standard_ubuntu.id)
  
  instance_type = "t3.micro"
}
```
