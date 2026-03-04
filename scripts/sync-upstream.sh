#!/bin/bash
################################################################################
# sync-upstream.sh
#
# Syncs modules and root-level files from the upstream terraform-rhcs-rosa-hcp
# repo into this fork. Both repos share the same root module structure; the only
# difference is that our root files use numbered prefixes (e.g. 20-main.tf).
#
# Usage:
#   ./scripts/sync-upstream.sh [command] [options]
#
# Commands:
#   status       Show which upstream modules have changes (default)
#   diff <mod>   Show diff for a specific module (or "all" / "root")
#   sync <mod>   Sync a specific module from upstream (creates a branch)
#   sync-all     Sync all shared modules from upstream (creates a branch)
#
# The script never modifies your current branch directly. It creates a
# sync branch so you can review changes before merging.
################################################################################

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"
UPSTREAM_REF="${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

# Modules that exist in both upstream and local repos.
# Modules only in the local repo (argocd-application, gitops-template-processor,
# keycloak-oauth, openshift-gitops) are never touched.
SHARED_MODULES=(
  account-iam-resources
  bastion-host
  idp
  image-mirrors
  kubelet-configs
  machine-pool
  oidc-config-and-provider
  operator-roles
  rosa-cluster-hcp
  shared-vpc-resources
  vpc
)

# Upstream root-level files that map to our numbered root files.
# Format: "upstream_path:local_path"
# These are shown in diff/status but NOT auto-synced (too divergent).
ROOT_MAPPINGS=(
  "main.tf:20-main.tf"
  "variables.tf:01-variables-cluster.tf"
  "outputs.tf:90-outputs.tf"
  "versions.tf:00-providers.tf"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ensure_upstream() {
  if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
    echo -e "${YELLOW}Adding upstream remote...${NC}"
    git remote add "$UPSTREAM_REMOTE" https://github.com/terraform-redhat/terraform-rhcs-rosa-hcp.git
  fi
  echo -e "${CYAN}Fetching ${UPSTREAM_REMOTE}...${NC}"
  git fetch "$UPSTREAM_REMOTE" --quiet
}

cmd_status() {
  ensure_upstream

  local local_head
  local_head=$(git rev-parse HEAD)
  local upstream_head
  upstream_head=$(git rev-parse "$UPSTREAM_REF")

  echo ""
  echo -e "${BOLD}Upstream sync status${NC}"
  echo -e "  Local HEAD:    $(git rev-parse --short HEAD) ($(git branch --show-current))"
  echo -e "  Upstream HEAD: $(git rev-parse --short $UPSTREAM_REF)"
  echo -e "  Latest tag:    $(git describe --tags --abbrev=0 $UPSTREAM_REF 2>/dev/null || echo 'none')"
  echo ""

  echo -e "${BOLD}Shared modules:${NC}"
  local has_changes=false
  for mod in "${SHARED_MODULES[@]}"; do
    local diff_stat
    diff_stat=$(git diff "$local_head".."$upstream_head" --stat -- "modules/${mod}/" 2>/dev/null || true)
    if [[ -n "$diff_stat" ]]; then
      local file_count
      file_count=$(echo "$diff_stat" | grep -c '|' || true)
      echo -e "  ${YELLOW}*${NC} modules/${mod}/  ${YELLOW}(${file_count} file(s) changed)${NC}"
      has_changes=true
    else
      echo -e "  ${GREEN}✓${NC} modules/${mod}/"
    fi
  done

  if [[ "$has_changes" == "false" ]]; then
    echo ""
    echo -e "${GREEN}All shared modules are up to date with upstream.${NC}"
  else
    echo ""
    echo -e "Run ${CYAN}./scripts/sync-upstream.sh diff <module>${NC} to see changes."
    echo -e "Run ${CYAN}./scripts/sync-upstream.sh sync <module>${NC} to apply changes."
  fi

  echo ""
  echo -e "${BOLD}Root module files (manual sync required):${NC}"
  for mapping in "${ROOT_MAPPINGS[@]}"; do
    local upstream_file="${mapping%%:*}"
    local local_file="${mapping##*:}"
    local diff_lines
    diff_lines=$(git diff "$local_head".."$upstream_head" --stat -- "$upstream_file" 2>/dev/null || true)
    if [[ -n "$diff_lines" ]]; then
      echo -e "  ${YELLOW}*${NC} ${upstream_file} -> ${local_file}  ${YELLOW}(changed)${NC}"
    else
      echo -e "  ${GREEN}✓${NC} ${upstream_file} -> ${local_file}"
    fi
  done
  echo ""
}

cmd_diff() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo "Usage: $0 diff <module-name|all|root>"
    exit 1
  fi

  ensure_upstream

  if [[ "$target" == "all" ]]; then
    for mod in "${SHARED_MODULES[@]}"; do
      echo -e "\n${BOLD}=== modules/${mod} ===${NC}"
      git diff HEAD.."$UPSTREAM_REF" -- "modules/${mod}/" || true
    done
  elif [[ "$target" == "root" ]]; then
    for mapping in "${ROOT_MAPPINGS[@]}"; do
      local upstream_file="${mapping%%:*}"
      echo -e "\n${BOLD}=== ${upstream_file} ===${NC}"
      git diff HEAD.."$UPSTREAM_REF" -- "$upstream_file" || true
    done
  else
    echo -e "\n${BOLD}=== modules/${target} ===${NC}"
    git diff HEAD.."$UPSTREAM_REF" -- "modules/${target}/" || true
  fi
}

cmd_sync() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo "Usage: $0 sync <module-name>"
    exit 1
  fi

  ensure_upstream

  # Validate module name
  local found=false
  for mod in "${SHARED_MODULES[@]}"; do
    if [[ "$mod" == "$target" ]]; then
      found=true
      break
    fi
  done
  if [[ "$found" == "false" ]]; then
    echo -e "${RED}Error: '${target}' is not a shared upstream module.${NC}"
    echo "Shared modules: ${SHARED_MODULES[*]}"
    exit 1
  fi

  local current_branch
  current_branch=$(git branch --show-current)
  local sync_branch="sync-upstream/modules-${target}"
  local upstream_short
  upstream_short=$(git rev-parse --short "$UPSTREAM_REF")

  echo -e "${CYAN}Syncing modules/${target} from upstream (${upstream_short})...${NC}"

  # Check for uncommitted changes
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${RED}Error: You have uncommitted changes. Commit or stash them first.${NC}"
    exit 1
  fi

  # Create sync branch
  git checkout -b "$sync_branch" 2>/dev/null || git checkout "$sync_branch"

  # Checkout the module files from upstream
  git checkout "$UPSTREAM_REF" -- "modules/${target}/"

  local changes
  changes=$(git diff --cached --stat)
  if [[ -z "$changes" ]]; then
    echo -e "${GREEN}modules/${target} is already up to date.${NC}"
    git checkout "$current_branch"
    git branch -d "$sync_branch" 2>/dev/null || true
    return
  fi

  echo -e "\n${BOLD}Changes staged:${NC}"
  git diff --cached --stat

  echo ""
  echo -e "${YELLOW}Files from upstream have been staged on branch '${sync_branch}'.${NC}"
  echo -e "Review the changes, then:"
  echo -e "  ${CYAN}git diff --cached${NC}                    # review in detail"
  echo -e "  ${CYAN}git commit -m 'sync modules/${target} from upstream'${NC}"
  echo -e "  ${CYAN}git checkout ${current_branch} && git merge ${sync_branch}${NC}"
  echo ""
}

cmd_sync_all() {
  ensure_upstream

  local current_branch
  current_branch=$(git branch --show-current)
  local sync_branch="sync-upstream/all-modules"
  local upstream_short
  upstream_short=$(git rev-parse --short "$UPSTREAM_REF")

  echo -e "${CYAN}Syncing all shared modules from upstream (${upstream_short})...${NC}"

  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${RED}Error: You have uncommitted changes. Commit or stash them first.${NC}"
    exit 1
  fi

  git checkout -b "$sync_branch" 2>/dev/null || {
    git checkout "$sync_branch"
    git reset --hard "$current_branch"
  }

  for mod in "${SHARED_MODULES[@]}"; do
    git checkout "$UPSTREAM_REF" -- "modules/${mod}/" 2>/dev/null || true
  done

  local changes
  changes=$(git diff --cached --stat)
  if [[ -z "$changes" ]]; then
    echo -e "${GREEN}All shared modules are already up to date.${NC}"
    git checkout "$current_branch"
    git branch -d "$sync_branch" 2>/dev/null || true
    return
  fi

  echo -e "\n${BOLD}Changes staged:${NC}"
  git diff --cached --stat

  echo ""
  echo -e "${YELLOW}All upstream module files staged on branch '${sync_branch}'.${NC}"
  echo -e "Review the changes, then:"
  echo -e "  ${CYAN}git diff --cached${NC}                    # review in detail"
  echo -e "  ${CYAN}git commit -m 'sync all modules from upstream ${upstream_short}'${NC}"
  echo -e "  ${CYAN}git checkout ${current_branch} && git merge ${sync_branch}${NC}"
  echo ""
}

# --- Main ---
command="${1:-status}"
shift || true

case "$command" in
  status)    cmd_status ;;
  diff)      cmd_diff "$@" ;;
  sync)      cmd_sync "$@" ;;
  sync-all)  cmd_sync_all ;;
  -h|--help|help)
    echo "Usage: $0 [status|diff|sync|sync-all] [options]"
    echo ""
    echo "Commands:"
    echo "  status            Show which upstream modules have changes (default)"
    echo "  diff <mod|all>    Show diff for a module, 'all', or 'root'"
    echo "  sync <module>     Sync one module from upstream (creates branch)"
    echo "  sync-all          Sync all shared modules (creates branch)"
    ;;
  *)
    echo "Unknown command: $command"
    echo "Run '$0 --help' for usage."
    exit 1
    ;;
esac
