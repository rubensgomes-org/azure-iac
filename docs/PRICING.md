# Pricing Reference

Cost model for the resources modules 01 (resource groups), 02 (networking),
04 (managed identities), 05 (key vault), 06 (acr), 10 (container app
environment), and 11 (container apps) provision, assuming no container app
is receiving traffic and `min_replicas = 0` (the module default). Prices are
Azure retail list prices, USD, `centralus`, as of September 2026 — verify
current rates against the links below before budgeting.

## Fixed-cost resources

These bill a flat fee regardless of usage.

| Resource                 | Why                                                          | Daily  | Weekly | Monthly |
|---------------------------|--------------------------------------------------------------|--------|--------|---------|
| ACR (Basic SKU)           | Flat SKU fee; 10 GiB storage included                        | $0.167 | $1.17  | $5.08   |
| 5 private DNS zones       | `02-networking` always creates all five, at $0.50/zone/month | $0.082 | $0.58  | $2.50   |
| **Total**                 |                                                                | **$0.25** | **$1.74** | **$7.58** |

## Usage-based resources (near-$0 while idle)

| Resource                        | Billing model                                                    |
|----------------------------------|-------------------------------------------------------------------|
| Container App Environment + apps | Consumption plan has no idle charge; billed per-second only while a replica runs |
| Key Vault (Standard)             | $0.03 per 10,000 operations, no monthly base fee                  |
| Log Analytics workspace          | Pay-per-GB ingested, first 5 GB/month free, no base workspace fee |
| Resource groups, VNet, subnets, NSGs, managed identity | Never billed                                 |

## Caveats

- List prices vary by region, currency, and any enterprise/dev agreement
  discount — treat this table as a sanity check, not a bill.
- Excludes the Terraform state backend (`bootstrap-backend`'s storage
  account), which is billed separately and negligible.
- For the actual bill, use Cost Management + Billing in the Azure Portal,
  scoped to this estate's resource groups.

## Sources

- [Container Registry pricing](https://azure.microsoft.com/en-us/pricing/details/container-registry/)
- [Container Apps pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/)
- [Azure DNS pricing](https://azure.microsoft.com/en-us/pricing/details/dns/)
- [Azure Monitor pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/)
- [Key Vault pricing](https://azure.microsoft.com/en-us/pricing/details/key-vault/)
