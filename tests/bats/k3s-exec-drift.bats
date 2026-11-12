#!/usr/bin/env bats
# tests/bats/k3s-exec-drift.bats — ansible/roles/k3s_server/files/k3s-exec-drift.sh
#
# The script decides whether the k3s roles re-run the installer at the same
# version. A false "in-sync" means a changed argument never reaches the node; a
# false "drift" restarts k3s on every run. Both are pinned down here against
# units written the way get.k3s.io writes them.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/ansible/roles/k3s_server/files/k3s-exec-drift.sh"

setup() {
  UNIT="${BATS_TEST_TMPDIR}/k3s.service"
}

# installer_unit <arg>... — a unit in get.k3s.io's layout: one single-quoted
# argument per line, a quote inside an argument escaped as '\''.
installer_unit() {
  {
    printf '[Unit]\nDescription=Lightweight Kubernetes\n\n[Service]\nType=notify\n'
    printf 'ExecStart=/usr/local/bin/k3s \\\n'
    printf '    server \\\n'
    local a
    for a in "$@"; do
      printf "\t'%s' \\\\\n" "${a//\'/\'\\\'\'}"
    done
    printf '\n'
    printf 'KillMode=process\n'
  } > "$UNIT"
}

@test "a missing unit is reported as absent" {
  K3S_DESIRED_EXEC="server" run "$SCRIPT" "${BATS_TEST_TMPDIR}/nope.service"
  [ "$status" -eq 0 ]
  [ "$output" = "absent" ]
}

@test "the same arguments are in sync" {
  installer_unit --node-ip 10.0.0.2 --disable traefik
  K3S_DESIRED_EXEC="server --node-ip 10.0.0.2 --disable traefik" run "$SCRIPT" "$UNIT"
  [ "$status" -eq 0 ]
  [ "$output" = "in-sync" ]
}

@test "reordered arguments are still in sync" {
  installer_unit --disable traefik --node-ip 10.0.0.2
  K3S_DESIRED_EXEC="server --node-ip 10.0.0.2 --disable traefik" run "$SCRIPT" "$UNIT"
  [ "$output" = "in-sync" ]
}

@test "whitespace and newlines in the wanted string do not matter" {
  installer_unit --node-ip 10.0.0.2
  K3S_DESIRED_EXEC=$'server\n   --node-ip   10.0.0.2  \t' run "$SCRIPT" "$UNIT"
  [ "$output" = "in-sync" ]
}

@test "a changed argument is drift, with both sides listed" {
  installer_unit --node-ip 10.0.0.2
  K3S_DESIRED_EXEC="server --node-ip 10.0.0.9" run "$SCRIPT" "$UNIT"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "drift" ]
  [[ "$output" == *"+ 10.0.0.9"* ]]
  [[ "$output" == *"- 10.0.0.2"* ]]
}

@test "an added flag is drift" {
  installer_unit --node-ip 10.0.0.2
  K3S_DESIRED_EXEC="server --node-ip 10.0.0.2 --kube-apiserver-arg=audit-policy-file=/x" run "$SCRIPT" "$UNIT"
  [ "${lines[0]}" = "drift" ]
  [[ "$output" == *"+ --kube-apiserver-arg=audit-policy-file=/x"* ]]
}

@test "a repeated flag counts: one occurrence less is drift" {
  installer_unit --disable traefik --disable servicelb
  K3S_DESIRED_EXEC="server --disable traefik" run "$SCRIPT" "$UNIT"
  [ "${lines[0]}" = "drift" ]
  [[ "$output" == *"- servicelb"* ]]
}

@test "an argument holding a single quote round-trips" {
  installer_unit "--node-label=note=it's"
  K3S_DESIRED_EXEC="server --node-label=note=it's" run "$SCRIPT" "$UNIT"
  [ "$output" = "in-sync" ]
}

@test "a hand-written one-line ExecStart is read too" {
  printf '[Service]\nExecStart=/usr/local/bin/k3s server --node-ip 10.0.0.2\n' > "$UNIT"
  K3S_DESIRED_EXEC="server --node-ip 10.0.0.2" run "$SCRIPT" "$UNIT"
  [ "$output" = "in-sync" ]
}

@test "lines after the ExecStart block are not read as arguments" {
  installer_unit --node-ip 10.0.0.2
  printf 'Restart=always\n' >> "$UNIT"
  K3S_DESIRED_EXEC="server --node-ip 10.0.0.2" run "$SCRIPT" "$UNIT"
  [ "$output" = "in-sync" ]
}

@test "an unset K3S_DESIRED_EXEC is a usage error" {
  installer_unit --node-ip 10.0.0.2
  run env -u K3S_DESIRED_EXEC "$SCRIPT" "$UNIT"
  [ "$status" -eq 2 ]
}
