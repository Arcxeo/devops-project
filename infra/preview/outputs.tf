output "namespace" {
  value = kubernetes_namespace_v1.preview.metadata[0].name
}

output "service" {
  value = kubernetes_service_v1.app.metadata[0].name
}
