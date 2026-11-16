# Glossary

Terms with a fixed meaning in this repository. Code, docs and commit messages
use them in exactly this sense.

## Vault

**Vault bootstrap**
: Everything between a running Vault pod and a Vault that External Secrets can
  read from: initialise, unseal, configure. Implemented by `lib/vault.sh`; seed
  is not part of it.

**Initialise**
: The one-time creation of the unseal keys and the root token
  (`vault operator init`), done by `task vault:init` on a fresh Vault. The keys
  and token are printed once and never stored.

**Unseal**
: Feeding unseal keys until Vault reports unsealed. Needed after every pod
  restart. Stops at the threshold, so not every key is used.

**Configure**
: The idempotent setup of engines, auth methods, policies and roles: KV v2 at
  `secret/`, Kubernetes auth, the policy directory, the External Secrets role,
  and OIDC when all of its variables are set. Run by `task vault:configure`,
  and by `task vault:init` after initialise or unseal.

**Seed**
: Writing the platform's own secrets (OIDC client, Grafana, Traefik dashboard)
  into Vault from `.env`. Separate from configure: it decides what is stored,
  not how Vault is set up.

**Policy directory**
: The folder of `*.hcl` files that configure writes as Vault policies, each
  named after its file. `vault/policies/` by default; `VAULT_POLICY_DIR`
  replaces it.
