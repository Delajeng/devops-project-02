# Project 2 — Infrastructure as Code: Provision a Server
**Difficulty:** ⭐⭐ Beginner+ | **Time:** 4–6 hrs | **Follows:** Project 1 | **Leads into:** Project 3

---

## What you're building

A reproducible cloud server — provisioned by Terraform (the "what exists") and configured by Ansible (the "what's installed"). You'll end up with a VM running your Project 1 Docker image, deployed entirely from code with no manual clicking in a cloud console.

## What you'll learn

- Terraform: providers, resources, variables, state, `plan`/`apply`/`destroy`
- Ansible: inventory, playbooks, idempotency, roles
- The Terraform + Ansible division of labour (create infrastructure vs. configure it)
- SSH key management for automation
- How to NOT commit secrets to Git

## Architecture

```
Your laptop
    │
    ├─ terraform apply ──────────────► Cloud provider API
    │                                        │
    │                                        ▼
    │                                  VM created
    │                                  (Ubuntu 24.04)
    │                                  Public IP assigned
    │
    └─ ansible-playbook ──SSH──────► VM
                                          ├─ Install Docker
                                          ├─ Create app user
                                          ├─ Pull image from registry
                                          └─ Run container as systemd service
```

## Cloud vs. local

| | Cloud path | Local path |
|-|-----------|------------|
| VM | Any cloud free tier (see provider options below) | Multipass VM (`multipass launch`) |
| Terraform provider | `hashicorp/aws`, `hashicorp/azurerm`, or `digitalocean/digitalocean` | `hashicorp/local` or Multipass |
| Cost | Free (within free tier limits) | Free |

**Cloud provider free tier options:**
- **AWS:** `t2.micro` or `t3.micro` — 750 hrs/month free for 12 months
- **Azure:** `B1s` — 750 hrs/month free for 12 months
- **GCP:** `e2-micro` — always free (no 12-month limit), best option
- **DigitalOcean/Hetzner:** Not free, but cheapest paid (~$4-6/month) and simplest API

This README uses **DigitalOcean** as the example (simplest Terraform provider for beginners) with notes for AWS/GCP/Azure where they differ significantly.

---

## Prerequisites

- Terraform installed (`terraform version`)
- Ansible installed (Linux/Mac/WSL2: `pip install ansible`)
- An SSH key pair on your laptop (generate with `ssh-keygen -t ed25519 -C "devops-project-02"`)
- A cloud account (DigitalOcean, AWS, GCP, or Azure)
- Project 1 image on Docker Hub (or use any public image)

---

## Step-by-step

### Step 1 — Create the project repo

```bash
mkdir devops-project-02
cd devops-project-02
git init
git checkout -b main
```

Create `.gitignore` — **do this first before creating any Terraform files:**

```
# Terraform
*.tfstate
*.tfstate.*
*.tfvars
.terraform/
.terraform.lock.hcl
crash.log

# Ansible
*.retry
inventory/hosts.ini
group_vars/*/vault_real.yml

# General
.env
*.pem
id_rsa
id_ed25519
```

### Step 2 — Terraform: provider and variables

Create `terraform/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}
```

Create `terraform/variables.tf`:

```hcl
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name of SSH key already uploaded to DigitalOcean"
  type        = string
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "fra1"  # Frankfurt — change to closest region
}

variable "droplet_size" {
  description = "Droplet size"
  type        = string
  default     = "s-1vcpu-1gb"  # cheapest: ~$6/month, destroy when done
}

variable "app_image" {
  description = "Docker image to run on the server"
  type        = string
  default     = "YOUR-DOCKERHUB-USERNAME/devops-project-01:latest"
}
```

Create `terraform/terraform.tfvars.example` (commit this — it's a template, not real values):

```hcl
# Copy to terraform.tfvars and fill in real values
# terraform.tfvars is gitignored — never commit it
do_token     = "your-digitalocean-api-token-here"
ssh_key_name = "your-ssh-key-name-in-do-dashboard"
region       = "fra1"
app_image    = "yourusername/devops-project-01:latest"
```

Create `terraform/main.tf`:

```hcl
provider "digitalocean" {
  token = var.do_token
}

# Look up the SSH key you uploaded to DigitalOcean
data "digitalocean_ssh_key" "default" {
  name = var.ssh_key_name
}

# The server
resource "digitalocean_droplet" "app_server" {
  name   = "devops-project-02"
  region = var.region
  size   = var.droplet_size
  image  = "ubuntu-24-04-x64"

  ssh_keys = [data.digitalocean_ssh_key.default.id]

  tags = ["devops-project", "project-02"]
}

# Output the public IP so Ansible can use it
output "server_ip" {
  value       = digitalocean_droplet.app_server.ipv4_address
  description = "Public IP of the provisioned server"
}
```

Create `terraform/terraform.tfvars` (gitignored — your real values):

```hcl
do_token     = "dop_v1_your_actual_token_here"
ssh_key_name = "your-key-name"
```

**How to get a DigitalOcean API token:**
1. DigitalOcean dashboard → API → Generate New Token
2. Name it, set read+write scope
3. Copy immediately — only shown once

**How to upload your SSH key to DigitalOcean:**
1. Settings → Security → SSH Keys → Add SSH Key
2. Paste the contents of `~/.ssh/id_ed25519.pub`
3. Give it a name — this is the name you put in `ssh_key_name`

### Step 3 — Provision with Terraform

```bash
cd terraform

# Initialise (downloads the DigitalOcean provider)
terraform init

# Review the plan — read it fully before applying
terraform plan

# Apply — creates the server (~30 seconds)
terraform apply
# Type "yes" to confirm

# Note the output IP
# server_ip = "x.x.x.x"

# Test SSH access
ssh root@$(terraform output -raw server_ip)
# Should get a shell prompt
exit
```

### Step 4 — Ansible: inventory and config

Back in the root of the project:

```bash
mkdir -p ansible/inventory ansible/playbooks ansible/group_vars/all
```

Create `ansible/ansible.cfg`:

```ini
[defaults]
inventory = inventory/hosts.ini
host_key_checking = False
remote_user = root
private_key_file = ~/.ssh/id_ed25519

[privilege_escalation]
become = True
```

Create `ansible/inventory/hosts.ini.example` (committed — template only):

```ini
[app_servers]
app-server-01 ansible_host=YOUR_SERVER_IP

[all:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
```

Create `ansible/inventory/hosts.ini` (gitignored — real IP):

```ini
[app_servers]
app-server-01 ansible_host=X.X.X.X   # paste the IP from terraform output

[all:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
```

### Step 5 — Ansible: the playbook

Create `ansible/playbooks/setup-server.yml`:

```yaml
---
- name: Configure app server
  hosts: app_servers
  become: true

  vars:
    app_image: "{{ lookup('env', 'APP_IMAGE') | default('nginx:alpine', true) }}"
    app_port: 8080

  tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Install required packages
      ansible.builtin.apt:
        name:
          - ca-certificates
          - curl
          - gnupg
          - ufw
        state: present

    - name: Add Docker GPG key
      ansible.builtin.apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: Add Docker repository
      ansible.builtin.apt_repository:
        repo: "deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
        state: present

    - name: Install Docker Engine
      ansible.builtin.apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-compose-plugin
        state: present
        update_cache: true

    - name: Ensure Docker service is running
      ansible.builtin.service:
        name: docker
        state: started
        enabled: true

    - name: Configure UFW — allow SSH
      community.general.ufw:
        rule: allow
        port: "22"
        proto: tcp

    - name: Configure UFW — allow app port
      community.general.ufw:
        rule: allow
        port: "{{ app_port }}"
        proto: tcp

    - name: Enable UFW
      community.general.ufw:
        state: enabled
        policy: deny

    - name: Pull app image
      community.docker.docker_image:
        name: "{{ app_image }}"
        source: pull

    - name: Run app container
      community.docker.docker_container:
        name: app
        image: "{{ app_image }}"
        state: started
        restart_policy: unless-stopped
        ports:
          - "{{ app_port }}:8080"
        env:
          APP_VERSION: "prod"
```

### Step 6 — Install Ansible collections

```bash
cd ansible
ansible-galaxy collection install community.docker community.general
```

### Step 7 — Run the playbook

```bash
cd ansible

APP_IMAGE="delajeng987/devops-project-01:latest" \
  ansible-playbook playbooks/setup-server.yml -i inventory/hosts.ini

# Watch for any FAILED or UNREACHABLE lines
# All tasks should show "ok" or "changed" — never "failed"
```

Test your server:

```bash
SERVER_IP=$(cd terraform && terraform output -raw server_ip)
curl http://$SERVER_IP:8080
curl http://$SERVER_IP:8080/health
```

### Step 8 — Prove idempotency

Run the playbook again:

```bash
ansible-playbook playbooks/setup-server.yml -i inventory/hosts.ini
```

Every task should show `ok` (not `changed`) — the server is already in the desired state. This is what "idempotent" means: running the playbook twice produces the same result. If anything shows `changed` on the second run, investigate why.

### Step 9 — Commit and clean up

```bash
# In project root
git add .
git status
# CONFIRM: no terraform.tfvars, no hosts.ini, no .terraform/ in the list

git commit -m "project-02: Terraform + Ansible IaC server provisioning"
git push -u origin main
```

**Destroy when done** to avoid cloud costs:

```bash
cd terraform
terraform destroy
# Type "yes"
# Server deleted — you will NOT be billed for it after this
```

---

## AWS alternative (instead of DigitalOcean)

Replace `terraform/versions.tf` and `terraform/main.tf` with:

```hcl
# versions.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# main.tf
provider "aws" {
  region = var.region
}

resource "aws_key_pair" "deployer" {
  key_name   = "devops-project-02"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "aws_security_group" "app" {
  name = "devops-project-02-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0"  # Ubuntu 24.04 us-east-1 — check for your region
  instance_type = "t2.micro"               # free tier

  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  tags = { Name = "devops-project-02" }
}

output "server_ip" {
  value = aws_instance.app_server.public_ip
}
```

Set credentials via environment variables (never in tfvars):

```bash
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
terraform apply
```

## Local path — Multipass VM

```bash
# Install Multipass: https://multipass.run
multipass launch --name devops-02 --cpus 1 --memory 1G --disk 10G 24.04

# Get the IP
multipass info devops-02

# Use that IP in ansible/inventory/hosts.ini
# Change ansible_user to ubuntu (not root) for Multipass
# Run the playbook the same way
```

---

## Tutorials

- Terraform DigitalOcean quickstart: https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- Ansible getting started: https://docs.ansible.com/ansible/latest/getting_started/index.html
- Ansible community.docker collection: https://docs.ansible.com/ansible/latest/collections/community/docker/

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Error: 401 Unable to authenticate` (Terraform) | API token wrong or expired — regenerate |
| `UNREACHABLE` in Ansible | SSH key not accepted — check `ssh root@IP` manually first |
| `FAILED: No package matching 'docker-ce'` | Docker repo not added yet — check the apt_repository task ran |
| Server exists but app not running | Check `docker ps` on the server — look for port conflicts |
| Second playbook run shows many `changed` | Non-idempotent task — check which one and add proper state checking |

---

## Definition of done

- [ ] `terraform apply` creates a server from scratch
- [ ] `ansible-playbook` configures it and deploys the app
- [ ] App reachable at `http://<server-ip>:8080`
- [ ] Second Ansible run shows all tasks `ok` (idempotent)
- [ ] `terraform destroy` cleanly deletes the server
- [ ] `terraform.tfvars` and `hosts.ini` are NOT in GitHub
- [ ] `terraform.tfvars.example` and `hosts.ini.example` ARE in GitHub

**Previous:** [Project 1 — Containerise and Ship](../project-01-containerise-and-ship/README.md) | **Next:** [Project 3 — CI/CD Pipeline](../project-03-cicd-pipeline/README.md)
