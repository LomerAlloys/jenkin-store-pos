output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "instance_address" {
  description = "Address of the instance (public IP if it has one, otherwise private IP)"
  value       = aws_instance.app.public_ip != "" ? aws_instance.app.public_ip : aws_instance.app.private_ip
}

output "private_ip" {
  description = "Private IP of the instance"
  value       = aws_instance.app.private_ip
}

output "app_url" {
  description = "Where taskflow-api would listen"
  value       = "http://${aws_instance.app.public_ip != "" ? aws_instance.app.public_ip : aws_instance.app.private_ip}:8080"
}
