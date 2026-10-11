variable "host_project_id" {
  type        = string
  description = "GCP Project ID for network infrastructure"
}

variable "region" {
  type        = string
  description = "Default deployment region"
  default     = "us-central1"
}

variable "palo_alto_instance_group_self_link" {
  type        = string
  description = "Self-link of the instance group containing Palo Alto VMs"
}

variable "pa_vm1_self_link" {
  type        = string
  description = "Compute instance self-link for PA-VM-1"
}

variable "pa_vm2_self_link" {
  type        = string
  description = "Compute instance self-link for PA-VM-2"
}
