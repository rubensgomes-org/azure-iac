# modules/region-code/main.tf
# -----------------------------------------------------------------------------
# Maps an Azure region to the short code appended to resource names.
# region-codes.json is also read by scripts/region-code.sh; see
# docs/NAMING.md#region-codes.
# -----------------------------------------------------------------------------

variable "location" {
  description = "Azure region, e.g. \"eastus2\" or \"East US 2\"."
  type        = string

  validation {
    condition = contains(
      keys(jsondecode(file("${path.module}/region-codes.json"))),
      lower(replace(var.location, " ", "")),
    )
    error_message = "location has no code in modules/region-code/region-codes.json; add it from docs/NAMING.md#region-codes."
  }
}

locals {
  codes = jsondecode(file("${path.module}/region-codes.json"))
}

output "code" {
  description = "Short region code, e.g. \"eus2\"."
  value       = local.codes[lower(replace(var.location, " ", ""))]
}
