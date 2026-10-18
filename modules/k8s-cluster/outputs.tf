output "api_server_endpoint" { value = "${local.control_vip}:6443" }
output "api_virtual_ip" { value = local.control_vip }
output "control_plane_private_ips" { value = aws_instance.control_plane[*].private_ip }
output "control_plane_public_ips" { value = aws_instance.control_plane[*].public_ip }
output "worker_public_ips" { value = aws_instance.worker[*].public_ip }
