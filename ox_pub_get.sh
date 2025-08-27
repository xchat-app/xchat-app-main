#!/usr/bin/env bash
# =============================================================================
# ox_pub_get.sh
# Utility script to checkout specific branches for the 0xChat Lite repo and its
# sub-projects, then run `flutter pub get` for each package.
#
# Supported repositories & default branches:
#   1. Main project           → main  (flag: -m <branch>)
#   2. 0xchat-core            → upgrade/isar4 (fixed)
#   3. nostr-dart             → main  (flag: -n <branch>)
#   4. nostr-mls-package      → main  (flag: -l <branch>)
#   5. bitchat-flutter-plugin → master (flag: -b <branch>)
# =============================================================================

set -euo pipefail

main_path="$(pwd)"
core_path="${main_path}/packages/0xchat-core"
nostr_dart_path="${main_path}/packages/nostr-dart"
nostr_mls_path="${main_path}/packages/nostr-mls-package"
bitchat_path="${main_path}/packages/bitchat-flutter-plugin"

# Default branches
main_branch="main"
core_branch="upgrade/isar4"       # Fixed
nostr_branch="main"
mls_branch="main"
bitchat_branch="master"

usage() {
  cat <<EOF
Usage: ./ox_pub_get.sh [options]
Options:
  -m <branch>   Branch name for main project          (default: main)
  -n <branch>   Branch name for packages/nostr-dart   (default: main)
  -l <branch>   Branch name for packages/nostr-mls-package (default: main)
  -b <branch>   Branch name for packages/bitchat-flutter-plugin (default: master)
  -h            Show this help message
EOF
  exit 1
}

# ------------------------- Parse CLI arguments ------------------------------
while getopts ':m:n:l:b:h' opt; do
  case "$opt" in
    m) main_branch="$OPTARG" ;;
    n) nostr_branch="$OPTARG" ;;
    l) mls_branch="$OPTARG" ;;
    b) bitchat_branch="$OPTARG" ;;
    h) usage ;;
    :) echo "Option -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Invalid option: -$OPTARG"; usage ;;
  esac
done

# ------------------------- Helper functions ---------------------------------
log_stage() {
  echo "🚀 [STAGE] $1"
  echo "=================================="
}

log_step() {
  echo "📋 [STEP] $1"
}

log_success() {
  echo "✅ [SUCCESS] $1"
}

log_skip() {
  echo "⏭️  [SKIP] $1"
}

log_error() {
  echo "❌ [ERROR] $1"
}

# Check if directory is a git submodule
is_git_submodule() {
  local dir=$1
  [[ -f "$dir/.git" ]] && grep -q "gitdir:" "$dir/.git"
}

# Check if directory is a git repository
is_git_repo() {
  local dir=$1
  [[ -d "$dir/.git" ]] && ! is_git_submodule "$dir"
}

# Get commit ID and branch info for a repository
get_repo_info() {
  local dir=$1
  local repo_name=$(basename "$dir")
  
  if is_git_submodule "$dir" || is_git_repo "$dir"; then
    local commit_hash=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    local short_hash=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    local branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    local commit_msg=$(git -C "$dir" log -1 --pretty=format:"%s" 2>/dev/null)
    
    if [[ -n "$commit_hash" ]]; then
      echo "  📦 $repo_name"
      echo "     Branch: $branch"
      echo "     CID: $commit_hash"
      echo "     Short: $short_hash"
      echo "     Message: $commit_msg"
      echo ""
    fi
  fi
}

# Display all repository commit information
show_all_repo_cids() {
  log_stage "Repository Commit Information"
  echo "All repositories current commit IDs (CIDs):"
  echo ""
  
  get_repo_info "$main_path"
  get_repo_info "$core_path"
  get_repo_info "$nostr_dart_path"
  get_repo_info "$nostr_mls_path"
  get_repo_info "$bitchat_path"
}

checkout_branch() {
  local dir=$1
  local branch=$2
  local repo_name=$(basename "$dir")
  
  log_step "Checking out $repo_name to branch: $branch"
  
  if is_git_submodule "$dir"; then
    # Checkout specific branch in submodule
    if ! git -C "$dir" checkout "$branch"; then
      log_error "Failed to checkout branch '$branch' in submodule $repo_name"
      exit 1
    fi
    
    # Pull latest changes
    if ! git -C "$dir" pull --ff-only; then
      log_error "Failed to pull latest changes for submodule $repo_name"
      exit 1
    fi
  elif is_git_repo "$dir"; then
    echo "  $repo_name is a git repository, updating..."
    
    # Fetch latest changes
    echo "  Fetching latest changes..."
    if ! git -C "$dir" fetch --all --tags --prune; then
      log_error "Failed to fetch latest changes for $repo_name"
      exit 1
    fi
    
    # Check current branch
    local current_branch=$(git -C "$dir" branch --show-current)
    if [[ "$current_branch" == "$branch" ]]; then
      echo "  Already on target branch, pulling latest changes..."
      if ! git -C "$dir" pull --ff-only; then
        log_error "Failed to pull latest changes for $repo_name"
        exit 1
      fi
    else
      echo "  Switching from $current_branch to $branch..."
      if ! git -C "$dir" checkout "$branch"; then
        log_error "Failed to checkout branch '$branch' in $repo_name"
        exit 1
      fi
      if ! git -C "$dir" pull --ff-only; then
        log_error "Failed to pull latest changes for $repo_name"
        exit 1
      fi
    fi
  else
    log_skip "Directory $dir is not a git repo or submodule"
    return
  fi
  
  # Show current commit info
  local commit_hash=$(git -C "$dir" rev-parse --short HEAD)
  local commit_msg=$(git -C "$dir" log -1 --pretty=format:"%s")
  echo "  Current commit: $commit_hash - $commit_msg"
  
  log_success "$repo_name updated to latest $branch"
}

run_pub_get() {
  local dir=$1
  local repo_name=$(basename "$dir")
  
  log_step "Running flutter pub get in $repo_name"
  
  if [[ ! -f "$dir/pubspec.yaml" ]]; then
    log_skip "$repo_name has no pubspec.yaml"
    return
  fi
  
  if ! (cd "$dir" && flutter pub get); then
    log_error "Failed to run flutter pub get in $repo_name"
    exit 1
  fi
  
  log_success "flutter pub get completed for $repo_name"
}

# ------------------------- Main execution -----------------------------------
log_stage "Starting 0xChat Lite dependency setup"

log_stage "Step 1: Updating repository branches"
checkout_branch "$main_path" "$main_branch"
checkout_branch "$core_path" "$core_branch"
checkout_branch "$nostr_dart_path" "$nostr_branch"
checkout_branch "$nostr_mls_path" "$mls_branch"
checkout_branch "$bitchat_path" "$bitchat_branch"

log_stage "Step 2: Installing Flutter dependencies"
# Only run flutter pub get in the main project
run_pub_get "$main_path"

log_stage "Step 3: Repository Information"
show_all_repo_cids

log_stage "All done"
echo "🎉 Successfully completed all setup tasks!"