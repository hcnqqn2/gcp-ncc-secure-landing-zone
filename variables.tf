variable "host_project_id" {
  type        = string
  description = "The GCP project ID designated as the Shared VPC host project."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The primary region for deploying regional resources and subnets."
}

variable "service_project_ids" {
  type        = map(string)
  description = "Map of service project IDs keyed by environment and workload type (e.g., dev-gce, dev-gke, dev-gemini)."
}

variable "service_project_numbers" {
  type        = map(string)
  description = "Map of service project numbers keyed by environment and workload type, required for IAM robot service account bindings."
}

variable "palo_alto_instance_group_self_link" {
  type        = string
  description = "The self-link of the Palo Alto Networks managed instance group or backend instance group."
}

variable "pa_vm1_self_link" {
  type        = string
  description = "The self-link of Palo Alto firewall VM 1 for the router appliance center spoke."
}

variable "pa_vm2_self_link" {
  type        = string
  description = "The self-link of Palo Alto firewall VM 2 for the router appliance center spoke."
}
