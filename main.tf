terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.host_project_id
  region  = var.region
}

locals {
  environments = {
    prod = {
      cidr      = "10.10.1.0/24"
      pod_cidr  = "10.100.0.0/18"
      svc_cidr  = "10.101.0.0/20"
      psc_cidr  = "10.10.254.0/24"
    },
    dev = {
      cidr      = "10.20.1.0/24"
      pod_cidr  = "10.200.0.0/18"
      svc_cidr  = "10.201.0.0/20"
      psc_cidr  = "10.20.254.0/24"
    },
    test = {
      cidr      = "10.30.1.0/24"
      pod_cidr  = "10.210.0.0/18"
      svc_cidr  = "10.211.0.0/20"
      psc_cidr  = "10.30.254.0/24"
    }
  }
}

# 1. NCC HUB 
resource "google_network_connectivity_hub" "enterprise_hub" {
  name        = "enterprise-star-hub"
  description = "Global NCC Hub using Star Topology for inspection"
}
# 2. HUB VPC (EDGE SPOKE - HYBRID CONNECTIVITY)
resource "google_compute_network" "hub_vpc" {
  name                    = "hub-hybrid-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "hub_subnet" {
  name          = "hub-subnet-us-central1"
  ip_cidr_range = "10.199.0.0/24"
  region        = var.region
  network       = google_compute_network.hub_vpc.id
}

resource "google_compute_router" "hub_router" {
  name    = "hub-hybrid-router"
  region  = var.region
  network = google_compute_network.hub_vpc.name
  bgp {
    asn = 65001
  }
}

resource "google_network_connectivity_spoke" "hub_vpc_spoke" {
  name     = "hub-vpc-edge-spoke"
  hub      = google_network_connectivity_hub.enterprise_hub.id
  location = var.region
  group    = "edge"

  linked_vpc_network {
    uri = google_compute_network.hub_vpc.self_link
  }
}

# 3. SECURITY VPC (CENTER SPOKE - PALO ALTO INSPECTION)
resource "google_compute_network" "security_vpc" {
  name                    = "security-inspection-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "sec_trust_subnet" {
  name                     = "sec-trust-subnet"
  ip_cidr_range            = "10.200.1.0/24"
  region                   = var.region
  network                  = google_compute_network.security_vpc.id
  private_ip_google_access = true
}

resource "google_compute_router" "sec_router" {
  name    = "security-cloud-router"
  region  = var.region
  network = google_compute_network.security_vpc.name
  bgp {
    asn = 65002
  }
}

resource "google_compute_region_health_check" "pa_health_check" {
  name   = "pa-trust-health-check"
  region = var.region
  tcp_health_check {
    port = "22"
  }
}

resource "google_compute_region_backend_service" "pa_backend" {
  name                  = "pa-trust-backend-service"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.pa_health_check.id]

  backend {
    group = var.palo_alto_instance_group_self_link
  }
}

resource "google_compute_forwarding_rule" "pa_ilb_vip" {
  name                  = "pa-trust-ilb-vip"
  region                = var.region
  network               = google_compute_network.security_vpc.name
  subnetwork            = google_compute_subnetwork.sec_trust_subnet.name
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  ip_address            = "10.200.1.100"
}

# BGP Peering for PA-VM-1
resource "google_compute_router_interface" "to_pa1" {
  name       = "interface-to-pa1"
  router     = google_compute_router.sec_router.name
  region     = var.region
  subnetwork = google_compute_subnetwork.sec_trust_subnet.id
}

resource "google_compute_router_peer" "peer_pa1" {
  name            = "peer-to-pa1"
  router          = google_compute_router.sec_router.name
  region          = var.region
  peer_ip_address = "10.200.1.2" # Primary IP of PA-VM-1
  peer_asn        = 65002
  interface       = google_compute_router_interface.to_pa1.name
}

# BGP Peering for PA-VM-2
resource "google_compute_router_interface" "to_pa2" {
  name       = "interface-to-pa2"
  router     = google_compute_router.sec_router.name
  region     = var.region
  subnetwork = google_compute_subnetwork.sec_trust_subnet.id
}

resource "google_compute_router_peer" "peer_pa2" {
  name            = "peer-to-pa2"
  router          = google_compute_router.sec_router.name
  region          = var.region
  peer_ip_address = "10.200.1.3" # Primary IP of PA-VM-2
  peer_asn        = 65002
  interface       = google_compute_router_interface.to_pa2.name
}
resource "google_network_connectivity_spoke" "security_center_spoke" {
  name     = "security-router-appliance-center-spoke"
  hub      = google_network_connectivity_hub.enterprise_hub.id
  location = var.region
  group    = "center"

  linked_router_appliance_instances {
    instances {
      virtual_machine = var.pa_vm1_self_link
      ip_address      = "10.200.1.2"
    }
    instances {
      virtual_machine = var.pa_vm2_self_link
      ip_address      = "10.200.1.3"
    }
    site_to_site_data_transfer = true
  }
}

# 4. WORKLOAD SHARED VPCs (PROD, DEV, TEST) WITH SERVICE STACK CONFIGURATIONS
resource "google_compute_network" "shared_vpcs" {
  for_each                = local.environments
  name                    = "shared-vpc-${each.key}"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "shared_subnets" {
  for_each                 = local.environments
  name                     = "subnet-${each.key}-us-central1"
  ip_cidr_range            = each.value.cidr
  region                   = var.region
  network                  = google_compute_network.shared_vpcs[each.key].id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "gke-pods-${each.key}"
    ip_cidr_range = each.value.pod_cidr
  }

  secondary_ip_range {
    range_name    = "gke-services-${each.key}"
    ip_cidr_range = each.value.svc_cidr
  }
}

resource "google_network_connectivity_spoke" "edge_spokes" {
  for_each = local.environments
  name     = "spoke-${each.key}-edge"
  hub      = google_network_connectivity_hub.enterprise_hub.id
  location = var.region
  group    = "edge"

  linked_vpc_network {
    uri = google_compute_network.shared_vpcs[each.key].self_link
  }
}

# 5. PRIVATE SERVICE CONNECT (PSC) FOR CLOUD SQL ACROSS SPOKES
resource "google_compute_subnetwork" "psc_subnets" {
  for_each      = local.environments
  name          = "subnet-psc-${each.key}"
  ip_cidr_range = each.value.psc_cidr
  region        = var.region
  network       = google_compute_network.shared_vpcs[each.key].id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}
