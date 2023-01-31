output "service-account-id" {
  description = "Service Account ID"
  value       = confluent_service_account.sa-cloud.id
}

output "basic-cluster-crm" {
  description = "Basic cluster CRM"
  value       = confluent_kafka_cluster.basic.rbac_crn
}
