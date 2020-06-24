provider "google" {
  # Store credentials JSON as $GOOGLE_CREDENTIALS
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "dogvpc" {
  name                    = "${var.dogname}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "dogsubnet" {
  name          = "${var.dogname}-subnet"
  region        = var.region
  network       = google_compute_network.dogvpc.self_link
  ip_cidr_range = var.subnet_prefix
}

resource "google_compute_firewall" "http-server" {
  name    = "default-allow-ssh-http"
  network = google_compute_network.dogvpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  // Allow traffic from everywhere to instances with an http-server tag
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

resource "tls_private_key" "dogkey" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

data "local_file" "bits" {
    filename = "./assets/bits.txt"
}

resource "google_compute_instance" "doghouse" {
  name         = var.dogname
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["datadog", "tech-exercise", "http-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  // Local SSD disk
  // This will *not* work for f1-micro or g1-small sized instances
  # scratch_disk {
  #   interface = "SCSI"
  # }

  network_interface {
    subnetwork = google_compute_subnetwork.dogsubnet.self_link
    access_config {
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${chomp(tls_private_key.dogkey.public_key_openssh)} terraform"
  }

  provisioner "file" {
    source      = "assets/"
    destination = "/home/ubuntu/"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      timeout     = "300s"
      private_key = tls_private_key.dogkey.private_key_pem
      host        = google_compute_instance.doghouse.network_interface.0.access_config.0.nat_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sh -c 'cp /home/ubuntu/bits.txt /etc/motd'",
      "sudo DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=${var.dd_api_key} bash -c \"$$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)\""
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      timeout     = "300s"
      private_key = tls_private_key.dogkey.private_key_pem
      host        = google_compute_instance.doghouse.network_interface.0.access_config.0.nat_ip
    }
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}

# Write out the SSH key so we can access our instance
# Be sure to `chmod 600 dogkey.pem` to fix the permissions!
resource "local_file" "dog-ssh-key" {
  content = tls_private_key.dogkey.private_key_pem
  filename = "./dogkey.pem"
}