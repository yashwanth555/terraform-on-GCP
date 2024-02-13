terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}



provider "google" {
  credentials = file("C:\\Users\\spoors\\Downloads\\main-analog-412710-725622715c54.json")
  project     = "main-analog-412710"
  region      = "us-east1"
  zone        = "us-east1-b"
}

variable "node_countweb" {
  default = "3"
}

resource "google_compute_instance" "prod-webservers" {
  count = var.node_countweb
  #name = "battlegroundindia"
  name         = "terraform-prod-webservers-${count.index + 2}"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-focal-v20220712"
    }

  }
  network_interface {
    network = "default"
    access_config {}
  }


  #Install Softwares

    metadata = {
    startup-script = <<-EOF
    #! /bin/bash
    mkdir -p /opt/tomcats/tomcat1
    sudo apt-get update
    sudo apt-get install htop glances zip unzip sysstat wget   -y
    cd /opt/tomcats/
    sudo wget  https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.24/bin/apache-tomcat-9.0.24.zip
    unzip  /opt/tomcats/apache-tomcat-9.0.24.zip -d /opt/tomcats/
    cp -r /opt/tomcats/apache-tomcat-9.0.24/* /opt/tomcats/tomcat1/
    chmod a+x /opt/tomcats/tomcat1/bin/*.sh 
    EOF
  }

}
resource "google_compute_instance_group" "web-instancegroup" {
  name        = "terraform-web-instancegroup"
  description = "Terraform test instance group"


  instances = google_compute_instance.prod-webservers[*].self_link
  named_port {
    name = "http"
    port = "8080"
  }

  named_port {
    name = "https"
    port = "8443"
  }

  zone = "us-east1-b"
}

variable "node_countsync" {
  default = "3"
}

resource "google_compute_instance" "prod-syncservers" {
  count = var.node_countsync
  #name = "battlegroundindia"
  name         = "terraform-prod-syncservers${count.index + 2}"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-focal-v20220712"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }
  metadata = {
    startup-script = <<-EOF
    #! /bin/bash
    mkdir -p /opt/tomcats/tomcat1
    sudo apt-get update
    sudo apt-get install htop glances zip unzip sysstat wget   -y
    cd /opt/tomcats/
    sudo wget  https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.24/bin/apache-tomcat-9.0.24.zip
    unzip  /opt/tomcats/apache-tomcat-9.0.24.zip -d /opt/tomcats/
    cp -r /opt/tomcats/apache-tomcat-9.0.24/* /opt/tomcats/tomcat1/
    chmod a+x /opt/tomcats/tomcat1/bin/*.sh 
    EOF
  }
}

resource "google_compute_instance_group" "sync-instancegroup" {
  name        = "terraform-prod-sync-instancegroup"
  description = "Terraform sync servers instance group"

  instances = google_compute_instance.prod-syncservers[*].self_link

  named_port {
    name = "http"
    port = "8080"
  }

  named_port {
    name = "https"
    port = "8443"
  }

  zone = "us-east1-b"
}


resource "google_compute_backend_service" "web-backend-service" {
  name          = "web-backend-service-prod"
  health_checks = [google_compute_http_health_check.web-backend.id]

  backend {
    group = google_compute_instance_group.web-instancegroup.id
  }
}

resource "google_compute_http_health_check" "web-backend" {
  name               = "web-health-check"
  request_path       = "/effortx"
  check_interval_sec = 1
  timeout_sec        = 1
}

resource "google_compute_backend_service" "sync-backend-service" {
  name          = "sync-backend-service-prod"
  health_checks = [google_compute_http_health_check.sync-backend-service.id]

  backend {
    group = google_compute_instance_group.sync-instancegroup.id
  }
}

resource "google_compute_http_health_check" "sync-backend-service" {
  name               = "sync-health-check-prod"
  request_path       = "/mobile"
  check_interval_sec = 1
  timeout_sec        = 1
}

#creating  lb with unmanaged groups:

resource "google_compute_global_forwarding_rule" "global_forwarding_rule_sync" {
  name       = "global-forwarding-rule-sync"
  project    = "main-analog-412710"
  target     = google_compute_target_http_proxy.target_http_proxy.self_link
  port_range = "80"
}

# used by one or more global forwarding rule to route incoming HTTP requests to a URL map
resource "google_compute_target_http_proxy" "target_http_proxy" {
  name    = "proxy-sync"
  project = "main-analog-412710"
  url_map = google_compute_url_map.url_map_sync.self_link
}




resource "google_compute_health_check" "healthcheck-prod" {
  name               = "healthcheckprod"
  timeout_sec        = 1
  check_interval_sec = 1
  http_health_check {
    port = 80
  }
}


# defines a group of virtual machines that will serve traffic for load balancing
resource "google_compute_backend_service" "sync_default" {
  name = "sync-backend-service"
  #project                 = "main-analog-412710"
  port_name     = "http"
  protocol      = "HTTP"
  health_checks = ["${google_compute_health_check.healthcheck-prod.self_link}"]
  backend {
    group = google_compute_instance_group.sync-instancegroup.id
    #balancing_mode        = "RATE"
    max_rate_per_instance = 100
  }
  backend {
    group = google_compute_instance_group.web-instancegroup.id
    #balancing_mode        = "RATE"
    max_rate_per_instance = 100
  }
}


resource "google_compute_url_map" "url_map_sync" {
  name = "load-balancer-sync"
  #project         = "main-analog-412710"
  default_service = google_compute_backend_service.sync_default.self_link
}


# show external ip address of load balancer
output "load-balancer-ip-address" {
  value = google_compute_global_forwarding_rule.global_forwarding_rule_sync.ip_address
}


resource "google_compute_instance" "testserver" {
  #count = var.node_countsync
  #name = "battlegroundindia"
  name         = "terraform-testserver"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-focal-v20220712"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }
    metadata = {
    startup-script = <<-EOF
    #! /bin/bash
    mkdir -p /opt/tomcats/tomcat1
    sudo apt-get update
    sudo apt-get install htop glances zip unzip sysstat wget   -y
    cd /opt/tomcats/
    sudo wget  https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.24/bin/apache-tomcat-9.0.24.zip
    unzip  /opt/tomcats/apache-tomcat-9.0.24.zip -d /opt/tomcats/
    cp -r /opt/tomcats/apache-tomcat-9.0.24/* /opt/tomcats/tomcat1/
    chmod a+x /opt/tomcats/tomcat1/bin/*.sh 
    EOF
  }
}






resource "google_compute_network" "vpc_network" {
  name = "vpc-network"
  delete_default_routes_on_create = false
  auto_create_subnetworks = true
  routing_mode = "REGIONAL"  
}

#adding subnets:

/*
resource"google_compute_subnetwork""vpc_subnet" {
#count= 2
name="vpc-subnetwork"
ip_cidr_range= "192.168.76.0/24"
region="us-east1"
network=google_compute_network.vpc_network.id
private_ip_google_access =true
}

*/
