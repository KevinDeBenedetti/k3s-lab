# Module: makefiles/00-lib.mk
# ──────────────────────────────────────────────────────────────────────────────
# Dual-mode script execution helpers
#
# k3s-lab can be used in two ways:
#   LOCAL  — clone the repo; K3S_LAB := $(PWD) is set in the root Makefile.
#             Scripts are scp'd to remote hosts or run directly from disk.
#   REMOTE — infra fetches this .mk file via curl; K3S_LAB is empty.
#             Scripts are fetched on-demand from K3S_LAB_RAW (GitHub raw).
#
# Macros (use with $(call ...)):
#   run-remote-script(rel-path, host, env-prefix)
#     Run a script on a remote SSH host.
#     rel-path   — path relative to k3s-lab root, e.g. k3s/install-master.sh
#     host       — target hostname/IP
#     env-prefix — space-separated VAR=value pairs prepended to the command
#
#   run-local-script(rel-path, args...)
#     Run a script on the local machine.
#     rel-path — path relative to k3s-lab root, e.g. scripts/get-kubeconfig.sh
#     args     — positional arguments forwarded to the script
# ──────────────────────────────────────────────────────────────────────────────

ifdef K3S_LAB

# ── Local mode: K3S_LAB points to the cloned repo ────────────────────────────

# scp the script to /tmp on the remote host, execute with env-prefix, then clean up.
define run-remote-script
scp -i $(SSH_KEY) -P $(SSH_PORT) \
    $(K3S_LAB)/$(1) $(SSH_USER)@$(2):/tmp/$(notdir $(1)) && \
ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(2) \
    "$(3) bash /tmp/$(notdir $(1)) && rm -f /tmp/$(notdir $(1))"
endef

# Run a local script directly from the repo checkout.
define run-local-script
K3S_LAB=$(K3S_LAB) K3S_LAB_RAW=$(K3S_LAB_RAW) \
SSH_KEY=$(SSH_KEY) SSH_PORT=$(SSH_PORT) \
bash $(K3S_LAB)/$(1) $(2)
endef

else

# ── Remote mode: K3S_LAB is empty — fetch scripts via curl ───────────────────

# Stream the script from GitHub raw into the remote host's bash via SSH.
define run-remote-script
ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(2) \
    "curl -fsSL $(K3S_LAB_RAW)/$(1) | $(3) bash"
endef

# Fetch and run the script locally via process substitution.
# K3S_LAB_RAW is exported so the script can source its lib/ helpers remotely.
define run-local-script
K3S_LAB= K3S_LAB_RAW=$(K3S_LAB_RAW) \
SSH_KEY=$(SSH_KEY) SSH_PORT=$(SSH_PORT) \
bash <(curl -fsSL $(K3S_LAB_RAW)/$(1)) $(2)
endef

endif
