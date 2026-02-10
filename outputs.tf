output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "aws_security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ec2_sg.id
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "session_manager_instructions" {
  value = "Connect using AWS Console -> EC2 -> Instance -> Connect -> Session Manager"
}