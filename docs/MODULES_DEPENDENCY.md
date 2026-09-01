# Module Dependency Reference

What each of the twelve module roots under `terraform/envs/dev/` needs applied
before it. Derived from the `data "terraform_remote_state"` blocks at the top of
each root's `main.tf` — that is the only thing wiring the roots together.

`terraform/bootstrap-backend/` is the prerequisite for all twelve: until it
exists, no root can `init`.

## Tree

Indented under a parent means "depends on it". The full list is on the right,
since most modules have more than one parent.

```
01-resource-groups                      (no module dependencies)
├── 02-networking                       ← 01
├── 03-log-analytics                    ← 01
├── 04-managed-identities               ← 01
│   ├── 05-key-vault                    ← 01, 04
│   ├── 06-acr                          ← 01, 04
│   ├── 07-storage                      ← 01, 04
│   ├── 08-service-bus                  ← 01, 04
│   └── 09-postgresql                   ← 01, 04
├── 10-container-app-environment        ← 01, 02, 03
├── 11-container-apps                   ← 01, 04, 06, 07, 08, 09, 10
└── 12-monitoring                       ← 01, 03, 05, 06, 07, 08, 09
```

## Table

| Module                         | Depends on                 | Why                                                                                  |
|--------------------------------|----------------------------|--------------------------------------------------------------------------------------|
| `01-resource-groups`           | —                          | Creates all five RGs.                                                                |
| `02-networking`                | 01                         | RG placement.                                                                        |
| `03-log-analytics`             | 01                         | RG placement.                                                                        |
| `04-managed-identities`        | 01                         | RG placement.                                                                        |
| `05-key-vault`                 | 01, 04                     | RG placement; UAMI data-plane role.                                                  |
| `06-acr`                       | 01, 04                     | RG placement; UAMI `AcrPull`.                                                        |
| `07-storage`                   | 01, 04                     | RG placement; UAMI Blob data role.                                                   |
| `08-service-bus`               | 01, 04                     | RG placement; UAMI Service Bus data role.                                            |
| `09-postgresql`                | 01, 04                     | RG placement; UAMI as a PG Entra role.                                               |
| `10-container-app-environment` | 01, 02, 03                 | RG placement; `snet-app`; workspace for CAE logs.                                    |
| `11-container-apps`            | 01, 04, 06, 07, 08, 09, 10 | Environment, registry, UAMI, and every backing service's endpoint as app config.     |
| `12-monitoring`                | 01, 03, 05, 06, 07, 08, 09 | Workspace, plus the resource ID of each service it attaches a diagnostic setting to. |

## Notes

- **A missing upstream fails at plan with *Unsupported attribute***, which does
  not name the real cause. The dependency is on the upstream's *state*, not its
  Azure resources.
- **01 and 04 are the two hubs.** 01 feeds all eleven; 04 feeds every module
  granting the shared UAMI a data-plane role (05–09, 11).
- **09 does not depend on 02.** `snet-pg` exists but is unused — PG runs in
  public-access mode. The delegated-subnet destroy hazard is 10/11 vs 02.
- **12 is a leaf**, and reads neither 10 nor 11.
- **Siblings are independent**: `{02, 03, 04}` after 01, `{05–09}` after 04,
  with 10 alongside them. `make apply` is sequential anyway.
