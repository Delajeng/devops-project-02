# Project 2 — Infrastructure as Code: Provision a Server

## What was built

A reproducible cloud server — provisioned by Terraform  and configured by Ansible 

## What was learnt

- Terraform: providers, resources, variables, state, `plan`/`apply`/`destroy`
- Ansible: inventory, playbooks, idempotency, roles
- The Terraform + Ansible division of labour (create infrastructure vs. configure it)
- SSH key management for automation
- How to NOT commit secrets to Git (.gitignore)

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

## Prerequisites

- Terraform installed (`terraform version`)
- Ansible installed (Linux/Mac/WSL2: `pip install ansible`)
- An SSH key pair (generate with `ssh-keygen -t ed25519 -C "devops-project-02"`)
- A cloud account (DigitalOcean, AWS, GCP, or Azure)
- Project 1 image on Docker Hub (or use any public image)

## Resources

- Terraform DigitalOcean quickstart: https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- Ansible getting started: https://docs.ansible.com/ansible/latest/getting_started/index.html
- Ansible community.docker collection: https://docs.ansible.com/ansible/latest/collections/community/docker/

---
