# Azure Windows Server Infrastructure — Terraform

Provisions two Windows Server 2022 VMs (Web Server and Monitor Server) in Azure using reusable, composable Terraform modules.

---

## Architecture Diagram

```
                              INTERNET
                                 │
               ┌─────────────────┴──────────────────┐
               │                                    │
        HTTP / HTTPS / RDP                         RDP
               │                                    │
               ▼                                    ▼
┌──────────────────────────────────────────────────────────────────┐
│                      AZURE SUBSCRIPTION                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │         Resource Group: rg-capstone-dev-eastus             │  │
│  │                                                            │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │    VNet: vnet-capstone-dev-eastus  (10.0.0.0/16)     │  │  │
│  │  │  ┌────────────────────────────────────────────────┐  │  │  │
│  │  │  │  Subnet: snet-capstone-dev-eastus (10.0.1.0/24)│  │  │  │
│  │  │  │                                                │  │  │  │
│  │  │  │  ┌──────────────────┐  ┌──────────────────┐   │  │  │  │
│  │  │  │  │   VM01 — WEB     │  │   VM02 — MON     │   │  │  │  │
│  │  │  │  │  vm-web01-...    │  │  vm-mon01-...    │   │  │  │  │
│  │  │  │  │  Win Server 2022 │  │  Win Server 2022 │   │  │  │  │
│  │  │  │  │                  │  │                  │   │  │  │  │
│  │  │  │  │  pip-web01 ──────┼──┼── pip-mon01      │   │  │  │  │
│  │  │  │  │  (Static PIP)   │  │  (Static PIP)    │   │  │  │  │
│  │  │  │  │                  │  │                  │   │  │  │  │
│  │  │  │  │  NSG: nsg-web    │  │  NSG: nsg-mon    │   │  │  │  │
│  │  │  │  │  ▸ TCP 80  (HTTP)│  │  ▸ TCP 3389(RDP) │   │  │  │  │
│  │  │  │  │  ▸ TCP 443(HTTPS)│  │                  │   │  │  │  │
│  │  │  │  │  ▸ TCP 3389 (RDP)│  │                  │   │  │  │  │
│  │  │  │  └──────────────────┘  └──────────────────┘   │  │  │  │
│  │  │  └────────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Folder Structure

```
capstoneproject/
├── main.tf                    # Root: resource group + module invocations
├── variables.tf               # All root input variable declarations
├── outputs.tf                 # Key infrastructure outputs
├── provider.tf                # AzureRM provider configuration
├── versions.tf                # Terraform + provider version constraints
├── locals.tf                  # Derived names and common tag map
├── terraform.tfvars.example   # Variable values template (copy → terraform.tfvars)
├── .gitignore                 # Excludes state files and secrets from version control
├── README.md                  # This file
│
├── modules/
│   ├── networking/            # VNet + Subnet
│   │   ├── versions.tf
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/              # NSG + inbound/outbound rules
│   │   ├── versions.tf
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── windows-vm/            # Public IP + NIC + NSG association + Windows VM
│       ├── versions.tf
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   ├── dev/terraform.tfvars   # Dev-specific variable overrides
│   ├── test/terraform.tfvars  # Test-specific variable overrides
│   └── prod/terraform.tfvars  # Prod-specific variable overrides
│
└── scripts/
    ├── bootstrap-web.ps1      # IIS installation script for Web Server
    └── bootstrap-monitor.ps1  # WinRM / Event Collector setup for Monitor Server
```

---

## Prerequisites

| Tool | Minimum Version |
|------|----------------|
| Terraform | >= 1.5.0 |
| Azure CLI | >= 2.50 |
| Azure Subscription | — |

---

## Quick Start

### 1. Authenticate to Azure

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

### 2. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set admin_password and review other values
```

Or supply the password securely via environment variable (recommended for CI/CD):

```bash
export TF_VAR_admin_password="YourStr0ng!Pass"
```

### 3. Initialise and deploy (dev environment)

```bash
terraform init
terraform plan  -var-file="environments/dev/terraform.tfvars"
terraform apply -var-file="environments/dev/terraform.tfvars"
```

### 4. Deploy to another environment

```bash
terraform apply -var-file="environments/prod/terraform.tfvars"
```

### 5. Destroy

```bash
terraform destroy -var-file="environments/dev/terraform.tfvars"
```

---

## Input Variables

| Name | Description | Type | Default | Sensitive |
|------|-------------|------|---------|-----------|
| `location` | Azure region | `string` | `"eastus"` | No |
| `environment` | Environment (dev/test/prod) | `string` | `"dev"` | No |
| `project` | Project name for naming | `string` | `"capstone"` | No |
| `vnet_address_space` | VNet CIDR blocks | `list(string)` | `["10.0.0.0/16"]` | No |
| `subnet_address_prefix` | Subnet CIDR | `string` | `"10.0.1.0/24"` | No |
| `vm_size` | Azure VM SKU | `string` | `"Standard_B2s"` | No |
| `admin_username` | VM administrator username | `string` | `"azureadmin"` | No |
| `admin_password` | VM administrator password | `string` | **required** | **Yes** |
| `os_disk_type` | OS disk storage tier | `string` | `"StandardSSD_LRS"` | No |
| `tags` | Extra tags for all resources | `map(string)` | `{}` | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Resource Group name |
| `vnet_name` | Virtual Network name |
| `subnet_name` | Subnet name |
| `web_vm_name` | Web Server VM resource name |
| `web_vm_public_ip` | Web Server public IP address |
| `web_vm_private_ip` | Web Server private IP address |
| `monitor_vm_name` | Monitor Server VM resource name |
| `monitor_vm_public_ip` | Monitor Server public IP address |
| `monitor_vm_private_ip` | Monitor Server private IP address |

---

## Resource Naming Convention

`<type>-<role>-<project>-<env>-<region>`

| Resource | Example Name |
|----------|-------------|
| Resource Group | `rg-capstone-dev-eastus` |
| Virtual Network | `vnet-capstone-dev-eastus` |
| Subnet | `snet-capstone-dev-eastus` |
| Web NSG | `nsg-web-capstone-dev` |
| Monitor NSG | `nsg-mon-capstone-dev` |
| Web VM | `vm-web01-capstone-dev` |
| Monitor VM | `vm-mon01-capstone-dev` |
| Web Public IP | `pip-web01-capstone-dev` |
| Monitor Public IP | `pip-mon01-capstone-dev` |

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate NSG per VM | Granular per-VM traffic control; no shared-rule coupling between web and monitor roles |
| NSG associated at NIC (not subnet) | Prevents accidental over-permission when multiple VMs share the same subnet |
| Standard SKU Static Public IPs | Required for zone-redundancy and load balancer compatibility; Static avoids IP churn on stop/start |
| Windows Server 2022 Datacenter | Latest GA Windows Server release available in Azure at project time |
| `computer_name` separate from `vm_name` | Azure resource name can be up to 64 chars; Windows NetBIOS hostname is limited to 15 chars |
| `StandardSSD_LRS` default OS disk | Good balance of performance and cost for non-prod; override to `Premium_LRS` for production |
| Three reusable modules | Clear separation of concerns — networking, security, and compute can be versioned and tested independently |
| Environment tfvars files | Single root configuration, multiple environment variable overrides; avoids code duplication |
| `boot_diagnostics {}` enabled | Managed-storage boot diagnostics at no extra cost; essential for console access during troubleshooting |

---

## Security Notes

- `admin_password` is declared `sensitive = true` — it will never appear in plan or apply output.
- Add `terraform.tfvars` to `.gitignore` (already included) — never commit credentials.
- RDP port 3389 is open to `Internet` as specified. **For production**, restrict `source_address_prefix` to known IP ranges or a VPN gateway.
- Consider enabling Azure Defender for Servers and Azure Monitor for production workloads.
