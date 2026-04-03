## Dynamic AMI Lookup
- Never hard-code AMI.
- Use a `data` block to get the latest AMI value:

```hcl
data "aws_ami" "latest_ami" {
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  owners = ["amazon"]
}
```

Then use the value like this:

```
resource "aws_instance" "example" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t2.micro"
```