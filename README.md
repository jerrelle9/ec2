# EC2 Provisioning with Terraform - Intern Assignment

## Overview

This project provisions a complete AWS EC2 infrastructure using Terraform, including:
- Custom VPC with public subnet
- Internet Gateway for external connectivity
- Security Group with firewall rules
- EC2 instance running Amazon Linux 2023
- Automated Apache web server installation

## Architecture

```
Internet
   |
   v
Internet Gateway
   |
   v
VPC (10.0.0.0/16)
   |
   v
Public Subnet (10.0.1.0/24)
   |
   v
Security Group (SSH + HTTP)
   |
   v
EC2 Instance (t2.micro)
```

## Prerequisites

1. **AWS Account** - Sign up at aws.amazon.com
2. **AWS CLI installed and configured**
   ```bash
   aws configure
   ```
3. **Terraform installed** - Version 1.0 or later
   ```bash
   terraform version
   ```
4. **SSH key pair generated**
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   ```

## File Structure

```
terraform-ec2-assignment/
├── main.tf         # Main infrastructure resources
├── variables.tf    # Input variables
├── data.tf         # Data sources
├── outputs.tf      # Output values
└── README.md       # This file
```

## Step-by-Step Deployment Guide

### Step 1: Clone/Download the Files

Ensure all `.tf` files are in the same directory.

### Step 2: Update Variables (Optional)

Edit `variables.tf` if you want to:
- Change the AWS region
- Use a different instance type
- Specify a different SSH key path

Or create a `terraform.tfvars` file:

```hcl
aws_region           = "us-west-2"
instance_type        = "t3.micro"
ssh_public_key_path  = "/path/to/your/key.pub"
```

### Step 3: Initialize Terraform

This downloads the AWS provider plugin:

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### Step 4: Validate Configuration

Check for syntax errors:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

### Step 5: Preview Changes

See what Terraform will create:

```bash
terraform plan
```

This shows all resources that will be created. Review carefully!

### Step 6: Apply Configuration

Create the infrastructure:

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output:**
```
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

instance_id = "i-1234567890abcdef0"
instance_public_ip = "54.123.45.67"
ssh_command = "ssh -i ~/.ssh/id_rsa ec2-user@54.123.45.67"
web_url = "http://54.123.45.67"
```

### Step 7: Test Your Instance

**Test SSH access:**
```bash
ssh -i ~/.ssh/id_rsa ec2-user@<your-public-ip>
```

**Test web server:**
Open your browser and navigate to the web_url from the outputs.

### Step 8: Clean Up (When Done)

**IMPORTANT:** To avoid AWS charges, destroy resources when finished:

```bash
terraform destroy
```

Type `yes` when prompted.

## Resources Explained

### 1. VPC (Virtual Private Cloud)
```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  ...
}
```
**Why:** Creates an isolated network for your resources. Think of it as your own private data center in AWS.

### 2. Internet Gateway
```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
```
**Why:** Allows resources in your VPC to communicate with the internet.

### 3. Subnet
```hcl
resource "aws_subnet" "public" {
  cidr_block = "10.0.1.0/24"
  ...
}
```
**Why:** A segment within the VPC where you place resources. "Public" means it can access the internet.

### 4. Security Group
```hcl
resource "aws_security_group" "ec2_sg" {
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    ...
  }
}
```
**Why:** Acts as a virtual firewall controlling inbound and outbound traffic.

### 5. EC2 Instance
```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  ...
}
```
**Why:** The actual virtual server that runs your applications.

## Why I Chose This Approach

### Resources vs. Modules

**I used resources because:**
1. **Learning** - You see exactly what's being created
2. **Transparency** - No hidden configurations
3. **Flexibility** - Easy to modify and understand
4. **Control** - Full control over every detail

**Modules would be better for:**
- Production environments
- Reusing code across projects
- Enforcing standards
- Complex architectures

### Design Decisions

1. **Amazon Linux 2023** - Latest, optimized for AWS, free tier eligible
2. **t2.micro** - Free tier eligible, perfect for learning
3. **Single public subnet** - Simplest architecture for this use case
4. **SSH + HTTP** - Basic access needed for web server testing
5. **Data sources for AMI** - Always gets the latest Amazon Linux image

## Common Issues & Troubleshooting

### Issue: "Error: No valid credential sources found"
**Solution:** Run `aws configure` and enter your credentials.

### Issue: "Error: creating EC2 Instance: UnauthorizedOperation"
**Solution:** Your AWS user needs EC2 permissions.

### Issue: "SSH connection refused"
**Solution:** Wait 2-3 minutes after instance creation for initialization.

### Issue: "Resource already exists"
**Solution:** Run `terraform destroy` first, or change resource names.

## Security Notes

⚠️ **Current Configuration Allows:**
- SSH from anywhere (0.0.0.0/0)
- HTTP from anywhere

**For production, you should:**
- Restrict SSH to your IP only
- Use AWS Systems Manager Session Manager (covered in Part 2)
- Enable VPC flow logs
- Use private subnets with NAT gateway
- Implement IAM roles

## Next Steps (Part 2)

Part 2 of the assignment will focus on:
- Removing direct IP-based SSH access
- Using AWS Systems Manager Session Manager
- Implementing IAM roles
- Improving security posture

## Cost Estimate

With free tier:
- EC2 t2.micro: Free (750 hours/month for 12 months)
- VPC, subnet, IGW: Free
- Data transfer: First 1 GB free, then ~$0.09/GB

**Total: $0** if staying within free tier limits

## Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices)

## Questions to Consider

1. What happens if you change the instance_type in variables.tf and run `terraform apply`?
2. How would you add a second EC2 instance?
3. What would break if you removed the Internet Gateway?
4. How could you make this code reusable across multiple environments (dev, staging, prod)?

## Deliverables Checklist

- [x] Terraform files (.tf) created
- [x] EC2 instance in a VPC
- [x] Security group configured
- [x] Instance type defined
- [x] Valid AMI used
- [x] Explanation of resources
- [x] Justification for choices

---

**Author:** Jerrelle Johnson
**Date:** February 2026  
**Assignment:** Terraform EC2 Provisioning - Part 1
