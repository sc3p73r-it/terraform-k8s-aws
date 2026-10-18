output "api_server_endpoint" { value = module.k8s_cluster.api_server_endpoint }
output "api_virtual_ip" { value = module.k8s_cluster.api_virtual_ip }
output "control_plane_private_ips" { value = module.k8s_cluster.control_plane_private_ips }
output "control_plane_public_ips" { value = module.k8s_cluster.control_plane_public_ips }
output "worker_public_ips" { value = module.k8s_cluster.worker_public_ips }
