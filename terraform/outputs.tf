output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.web_alb.dns_name
}

output "db_endpoint" {
  description = "The connection endpoint for the database"
  value       = aws_db_instance.default.endpoint
}

output "bastion_public_ip" {
  description = "The public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}