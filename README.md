# EC2 Provisioning with Terraform - Part 2: Secure Private Access

## Overview

Part 2 builds on Part 1 by implementing a **production-grade security architecture**. This project provisions:
- **Private EC2 instance** with NO public IP address
- **VPC Endpoints** for secure AWS service communication
- **AWS Systems Manager (SSM)** for browser-based shell access
- **IAM roles** for least-privilege access
- **Zero exposed ports** - no SSH keys required

## What Changed from Part 1?

| Feature | Part 1 (Public) | Part 2 (Private) |
|---------|----------------|------------------|
| **Subnet Type** | Public | Private |
| **Public IP** | Yes | No |
| **Internet Access** | Via Internet Gateway | Via VPC Endpoints only |
| **Access Method** | SSH (port 22) | SSM Session Manager |
| **Security Risk** | Exposed to internet | Completely isolated |
| **SSH Keys** | Required | Not needed |
| **Cost** | ~$0 (free tier) | ~$22/month (VPC endpoints) |

## Architecture

```
AWS Console (Session Manager)
        |
        v
    SSM Service
        |
        v
   VPC Endpoints (Interface)
   (ssm, ssmmessages, ec2messages)
        |
        v
VPC (10.0.0.0/16)
        |
        v
Private Subnet (10.0.1.0/24)
   [No Internet Gateway]
   [No NAT Gateway]
        |
        v
Security Group (HTTPS outbound only)
        |
        v
EC2 Instance (t2.micro)
  [No Public IP]
  [IAM Role with SSM permissions]
```

## Key Security Improvements

### 1. **No Public IP Address**
```hcl
associate_public_ip_address = false
```
The instance is completely unreachable from the internet.

### 2. **Private Subnet**
```hcl
map_public_ip_on_launch = false
```
Even if you wanted a public IP, the subnet won't allow it.

### 3. **No Ingress Rules**
```hcl
# EC2 Security Group has ZERO ingress rules
# Only egress allowed
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```
No inbound connections possible - not even from within AWS.

### 4. **VPC Endpoints Instead of Internet**
Instead of routing through the internet, the instance communicates directly with AWS services via private connections.

## Prerequisites

Same as Part 1, except:
- ❌ **No SSH key pair needed!**
- ✅ AWS CLI configured
- ✅ Terraform installed
- ✅ AWS account with appropriate permissions

## File Structure

```
terraform-ec2-assignment/
├── main.tf         # Infrastructure resources
├── variables.tf    # Input variables
├── data.tf         # Data sources
├── outputs.tf      # Output values
└── README.md       # This file
```

## Step-by-Step Deployment Guide

### Step 1: Initialize Terraform

```bash
terraform init
```

### Step 2: Review the Plan

```bash
terraform plan
```

**You should see approximately 13 resources:**
- 1 VPC
- 1 Private Subnet
- 1 Route Table + Association
- 2 Security Groups (EC2 + VPC Endpoints)
- 1 EC2 Instance
- 1 IAM Role
- 1 IAM Role Policy Attachment
- 1 IAM Instance Profile
- 3 VPC Endpoints (SSM, SSMMessages, EC2Messages)

### Step 3: Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Wait 3-5 minutes** after apply completes for:
- EC2 instance to fully boot
- SSM agent to start and register
- VPC endpoints to become available

### Step 4: Verify SSM Registration

Check if your instance is registered with Systems Manager:

```bash
aws ssm describe-instance-information --region <your-region>
```

Look for your instance ID in the output with `PingStatus: "Online"`.

### Step 5: Connect via Session Manager

**Option A: AWS Console (Recommended for first time)**
1. Go to AWS Console → EC2 → Instances
2. Select your instance
3. Click **Connect** button
4. Choose **Session Manager** tab
5. Click **Connect**

**Option B: AWS CLI**
```bash
aws ssm start-session --target <instance-id> --region <your-region>
```

**Option C: Using Terraform Output**
```bash
# The output provides the exact command
terraform output ssm_connect_command
```

### Step 6: Verify You're Connected

Once in the session:
```bash
# Check you're on the instance
whoami
# Output: ssm-user

# Check instance metadata
curl http://169.254.169.254/latest/meta-data/instance-id

# Verify no public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4
# Output: (should fail or return nothing)

# Check the status file from user data
cat /tmp/status.txt
```

### Step 7: Clean Up

```bash
terraform destroy
```

Type `yes` when prompted.

## Deep Dive: How VPC Endpoints Work

### Why Three Separate Endpoints?

Each endpoint serves a specific purpose:

**1. SSM Endpoint (`com.amazonaws.region.ssm`)**
- Main Systems Manager API
- Instance registration
- Retrieving commands and configurations

**2. SSM Messages Endpoint (`com.amazonaws.region.ssmmessages`)**
- Session Manager data channel
- Transmits your keystrokes and command output
- Real-time terminal session communication

**3. EC2 Messages Endpoint (`com.amazonaws.region.ec2messages`)**
- Instance messaging service
- Allows SSM agent to receive commands
- Enables Run Command functionality

### Without These Endpoints

If you removed even ONE endpoint, SSM would fail because:
- Instance couldn't register with SSM service
- Sessions couldn't transmit data
- Commands couldn't be delivered

### VPC Endpoint Types

```hcl
vpc_endpoint_type = "Interface"
```

**Interface Endpoints:**
- Create ENI (Elastic Network Interface) in your subnet
- Get private IP addresses
- Cost: ~$0.01/hour per endpoint
- Work with most AWS services

**Gateway Endpoints (not used here):**
- Free
- Only for S3 and DynamoDB
- Use route table entries instead of ENIs

### Private DNS

```hcl
private_dns_enabled = true
```

This allows the instance to use standard AWS service URLs like:
- `ssm.us-east-1.amazonaws.com`
- `ssmmessages.us-east-1.amazonaws.com`

Without this, you'd need to use endpoint-specific URLs.

## Deep Dive: IAM Roles for EC2

### The Three-Part System

**1. IAM Role**
```hcl
resource "aws_iam_role" "ec2_ssm_role" {
  assume_role_policy = jsonencode({
    # Allows EC2 service to assume this role
  })
}
```

**2. Policy Attachment**
```hcl
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

**3. Instance Profile**
```hcl
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}
```

### Why the Separation?

- **Role** = Set of permissions (what you can do)
- **Policy** = The actual permissions document
- **Instance Profile** = Container that attaches the role to EC2

### What Can the Instance Do?

The `AmazonSSMManagedInstanceCore` policy allows:
- Register with Systems Manager
- Send logs to CloudWatch (if configured)
- Receive and execute commands
- Upload inventory data

The instance **CANNOT**:
- Access S3 (unless you add that policy)
- Modify other EC2 instances
- Create AWS resources
- Access databases

## Security Analysis

### Attack Surface Comparison

**Part 1 (Public Instance):**
- ✅ SSH brute force attacks possible
- ✅ Port scanning possible
- ✅ DDoS possible
- ✅ Exploit of SSH vulnerabilities
- ❌ Need to manage SSH keys
- ❌ SSH access logged only on instance

**Part 2 (Private Instance):**
- ❌ No exposed ports
- ❌ Unreachable from internet
- ❌ No SSH keys to steal
- ✅ All access logged in CloudTrail
- ✅ IAM-based access control
- ✅ Centralized session recording

### What if the Instance is Compromised?

**Attacker capabilities:**
```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```

The attacker COULD:
- Make outbound connections to anywhere
- Exfiltrate data to external servers
- Download malicious tools (if they could reach them)

### How to Improve Further

**Option 1: Restrict Egress to AWS Services Only**
```hcl
egress {
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  cidr_blocks     = [aws_vpc.main.cidr_block]  # VPC only
}
```

**Option 2: Add VPC Flow Logs**
Monitor all network traffic for anomalies.

**Option 3: Use AWS PrivateLink**
Connect to third-party SaaS without internet access.

## Cost Analysis

### Monthly Costs (us-east-1)

| Resource | Cost |
|----------|------|
| EC2 t2.micro | $0 (free tier) or ~$8.50 |
| EBS 40GB gp3 | $0 (free tier) or ~$3.20 |
| VPC Endpoint (SSM) | ~$7.30 |
| VPC Endpoint (SSMMessages) | ~$7.30 |
| VPC Endpoint (EC2Messages) | ~$7.30 |
| Data Processing | ~$0.01/GB |
| **Total** | **~$22-34/month** |

### Cost Optimization Strategies

**1. Share Endpoints Across Subnets**
If you have multiple private subnets, attach all to the same endpoints.

**2. Use for Production Only**
For dev/test, consider Part 1's public approach if cost is a concern.

**3. NAT Gateway Alternative**
- If you need internet access: NAT Gateway = ~$32/month + data
- If SSM only: VPC Endpoints = ~$22/month (current approach is cheaper)

**4. Use AWS Systems Manager Endpoint for Multiple Services**
The same endpoints work for:
- Session Manager
- Run Command
- Patch Manager
- State Manager

## Alternative Approaches

### Approach 1: Public Subnet + Security Group (Part 1)
**Pros:** Free, simple, can download packages
**Cons:** Exposed to internet, requires SSH management
**Cost:** $0

### Approach 2: Private Subnet + VPC Endpoints (Current)
**Pros:** Most secure, no exposed ports, managed access
**Cons:** More expensive, can't download from internet
**Cost:** ~$22/month

### Approach 3: Private Subnet + NAT Gateway
**Pros:** Can download packages, still private
**Cons:** Most expensive, more complex
**Cost:** ~$32/month + $0.045/GB

### Approach 4: Hybrid (Best for Production)
- Private subnet with VPC endpoints for AWS services
- NAT Gateway for internet access (apt/yum updates)
- Bastion host in public subnet as backup access
**Cost:** ~$54/month

## Common Issues & Troubleshooting

### Issue: Instance Not Showing in Session Manager

**Check 1: Wait 3-5 minutes**
The SSM agent needs time to register.

**Check 2: Verify IAM role is attached**
```bash
aws ec2 describe-instances --instance-ids <id> --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

**Check 3: Verify VPC endpoints are available**
```bash
aws ec2 describe-vpc-endpoints --region <region>
```
All three should show `State: "available"`.

**Check 4: Security group on endpoints**
Must allow HTTPS (443) from the VPC CIDR block.

**Check 5: Check SSM agent status (if you can access via another method)**
```bash
sudo systemctl status amazon-ssm-agent
```

### Issue: "User: anonymous is not authorized to perform: ssm:StartSession"

**Solution:** You need IAM permissions. Add this policy to your IAM user:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ssm:StartSession",
      "ssm:TerminateSession"
    ],
    "Resource": "*"
  }]
}
```

### Issue: VPC Endpoint Creation Failed

**Solution:** Check your region supports VPC endpoints for SSM:
```bash
aws ec2 describe-vpc-endpoint-services --region <region> | grep ssm
```

### Issue: High Costs

**Solution:** Remember to destroy when not in use:
```bash
terraform destroy
```

VPC endpoints charge by the hour, even when not in use.

## Testing & Validation

### Test 1: Verify No Public IP
```bash
# Should return empty or fail
terraform output instance_public_ip
```

### Test 2: Verify SSM Connectivity
```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

### Test 3: Verify No Internet Access (from within session)
```bash
# Should fail
ping google.com

# Should fail
curl https://google.com
```

### Test 4: Verify AWS Service Access
```bash
# Should work (metadata service)
curl http://169.254.169.254/latest/meta-data/instance-id
```

### Test 5: Check IAM Role
```bash
# From within session
aws sts get-caller-identity
# Should show the EC2 role, not your user
```

## Real-World Use Cases

### When to Use This Architecture

✅ **Production databases** - No public access needed
✅ **Batch processing** - Jobs that don't need internet
✅ **Internal APIs** - Backend services
✅ **Compliance workloads** - HIPAA, PCI-DSS requirements
✅ **High-security applications** - Financial, government

### When NOT to Use This

❌ **Web servers** - Need to serve internet traffic (use ALB instead)
❌ **Dev environments** - Cost may not be justified
❌ **Applications needing package updates** - Need NAT Gateway
❌ **Learning/testing** - Part 1 is simpler and free

## Comparison: SSM vs Traditional SSH

| Feature | SSH | SSM Session Manager |
|---------|-----|---------------------|
| **Port Required** | 22 | None |
| **Public IP** | Required | Not required |
| **Key Management** | Manual | Not needed |
| **Access Control** | Key-based | IAM-based |
| **Audit Logging** | Instance logs only | CloudTrail |
| **Session Recording** | Manual setup | Built-in (if enabled) |
| **Bastion Host** | Often needed | Not needed |
| **MFA Support** | Manual | Native via IAM |
| **Browser Access** | No | Yes |

## Advanced Topics (Beyond This Assignment)

### 1. Session Manager Logging
Record all session activity to S3:
```hcl
resource "aws_ssm_document" "session_manager_prefs" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "1.0"
    inputs = {
      s3BucketName = aws_s3_bucket.session_logs.id
      cloudWatchLogGroupName = aws_cloudwatch_log_group.session_logs.name
    }
  })
}
```

### 2. Port Forwarding via SSM
Access private RDS databases from your laptop:
```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"portNumber":["3306"],"localPortNumber":["3306"]}'
```

### 3. Run Commands Without Sessions
Execute commands on multiple instances:
```bash
aws ssm send-command \
  --instance-ids "i-1234567890abcdef0" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo Hello World"]'
```

## Questions to Consider

1. **Why does removing even ONE VPC endpoint break SSM?**
   Each endpoint handles a different part of the communication pipeline.

2. **What would happen if you set `private_dns_enabled = false`?**
   The instance couldn't resolve standard AWS service URLs.

3. **Could you add a second EC2 instance using the same VPC endpoints?**
   Yes! Endpoints can be shared across all instances in the subnet.

4. **How would you allow the instance to download packages from the internet?**
   Add a NAT Gateway or use VPC endpoints for specific package repos.

5. **What's the difference between the IAM role and the instance profile?**
   The role defines permissions; the profile attaches the role to EC2.

6. **Why allow all outbound traffic in the EC2 security group?**
   It needs to reach the VPC endpoints on port 443, but egress rules could be tightened.

7. **If you wanted to access a private RDS database from this instance, what would you add?**
   Security group rule on RDS allowing traffic from the EC2 security group.

8. **How does SSM work without an exposed port?**
   The instance initiates outbound connections to AWS services; you don't connect TO the instance.

## Key Takeaways

### Security Lessons
- **Defense in depth:** Multiple layers (private subnet + no ingress + IAM)
- **Least privilege:** Instance has minimal permissions needed
- **Zero trust:** No assumptions about network security

### Cost vs. Security Trade-offs
- Free/cheap isn't always appropriate for production
- ~$22/month is reasonable for production security
- Know when each approach makes sense

### AWS Service Integration
- VPC Endpoints enable private AWS API access
- IAM roles eliminate credential management
- Systems Manager provides modern instance access

## Next Steps

After completing this assignment, explore:
1. **VPC Flow Logs** - Monitor all network traffic
2. **AWS Config** - Track configuration changes
3. **CloudWatch Alarms** - Alert on unusual activity
4. **Auto Scaling Groups** - Automatically scale instances
5. **Application Load Balancer** - Distribute traffic
6. **AWS Secrets Manager** - Manage database passwords
7. **Parameter Store** - Store configuration

## Additional Resources

- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/)
- [VPC Endpoints Pricing](https://aws.amazon.com/privatelink/pricing/)
- [IAM Roles for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [VPC Endpoint Services](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html)

## Deliverables Checklist

- [ ] Private subnet with no public IPs
- [ ] VPC endpoints for SSM, SSMMessages, EC2Messages
- [ ] IAM role with AmazonSSMManagedInstanceCore policy
- [ ] Security groups (EC2 + VPC endpoints)
- [ ] EC2 instance with IAM instance profile attached
- [ ] Successfully connect via Session Manager
- [ ] Verify no public IP assigned
- [ ] Document cost implications
- [ ] Explain security improvements over Part 1

---

**Author:** Jerrelle Johnson  
**Date:** February 2026  
**Assignment:** Terraform EC2 Provisioning - Part 2 (Secure Private Access)  
**Architecture:** Private EC2 with SSM via VPC Endpoints