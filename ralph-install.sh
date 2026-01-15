#!/bin/bash
set -eo pipefail

# =============================================================================
# Ralph Wiggum Loop Installer
# https://github.com/buker/ralph-playbook
# =============================================================================

SCRIPT_VERSION="1.0.0"
GITHUB_REPO="buker/ralph-playbook"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

# Core files to install: "source_path:dest_filename"
CORE_FILES=(
    "files/loop.sh:loop.sh"
    "files/PROMPT_build.md:PROMPT_build.md"
    "files/PROMPT_plan.md:PROMPT_plan.md"
    "files/AGENTS.md:AGENTS.md"
    "files/IMPLEMENTATION_PLAN.md:IMPLEMENTATION_PLAN.md"
)

# Optional MCP settings file
MCP_SOURCE=".claude/settings.local.json"
MCP_DEST="settings.local.json"

# Globals
ASSUME_YES="${ASSUME_YES:-false}"

# =============================================================================
# COLOR OUTPUT
# =============================================================================

setup_colors() {
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        DIM='\033[2m'
        RESET='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
    fi
}

print_header()  { echo -e "${BOLD}${BLUE}$1${RESET}"; }
print_success() { echo -e "${GREEN}[OK]${RESET} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
print_error()   { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
print_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
print_step()    { echo -e "${DIM}-->${RESET} $1"; }

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

die() {
    print_error "$1"
    exit "${2:-1}"
}

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    read -rp "$prompt" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

command_exists() {
    command -v "$1" &>/dev/null
}

backup_file() {
    local file="$1"
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$file" "$backup"
    echo "$backup"
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_step "Created directory: $dir"
    fi
}

# =============================================================================
# SOURCE FUNCTIONS
# =============================================================================

fetch_from_git() {
    local source_path="$1"
    local dest="$2"
    local url="${GITHUB_RAW_BASE}/${source_path}"

    if command_exists curl; then
        if ! curl -fsSL "$url" -o "$dest" 2>/dev/null; then
            print_error "Failed to fetch: $url"
            return 1
        fi
    elif command_exists wget; then
        if ! wget -q "$url" -O "$dest" 2>/dev/null; then
            print_error "Failed to fetch: $url"
            return 1
        fi
    else
        die "Neither curl nor wget found. Cannot fetch from git."
    fi
}

copy_from_local() {
    local source_dir="$1"
    local source_path="$2"
    local dest="$3"
    local full_source="${source_dir}/${source_path}"

    if [[ ! -f "$full_source" ]]; then
        print_error "Source file not found: $full_source"
        return 1
    fi

    cp "$full_source" "$dest"
}

# =============================================================================
# FILE HANDLING
# =============================================================================

handle_existing_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    if [[ "$ASSUME_YES" == "true" ]]; then
        local backup
        backup=$(backup_file "$file")
        print_step "Backed up to: $backup"
        return 0
    fi

    print_warning "File already exists: $file"
    echo "  Options:"
    echo "    [b] Backup existing file and replace"
    echo "    [s] Skip this file"
    echo "    [o] Overwrite without backup"

    while true; do
        read -rp "  Choice [b/s/o]: " choice
        case "$choice" in
            b|B)
                local backup
                backup=$(backup_file "$file")
                print_step "Backed up to: $backup"
                return 0
                ;;
            s|S)
                return 1
                ;;
            o|O)
                return 0
                ;;
            *)
                echo "  Invalid choice. Please enter b, s, or o."
                ;;
        esac
    done
}

install_file() {
    local source_mode="$1"
    local source_path="$2"
    local local_dir="$3"
    local dest="$4"
    local filename="$5"

    if ! handle_existing_file "$dest"; then
        print_step "Skipped: $filename"
        return 1
    fi

    if [[ "$source_mode" == "git" ]]; then
        fetch_from_git "$source_path" "$dest"
    else
        copy_from_local "$local_dir" "$source_path" "$dest"
    fi

    print_success "Installed: $filename"
    return 0
}

# =============================================================================
# INSTALL
# =============================================================================

do_install() {
    local source_mode="${1:-git}"
    local source_path="${2:-}"
    local install_mcp="${3:-false}"
    local run_scan="${4:-false}"
    local scan_model="${5:-opus}"

    print_header "Installing Ralph Wiggum Loop"
    echo ""

    if [[ "$source_mode" == "local" ]]; then
        if [[ -z "$source_path" ]]; then
            die "Local mode requires a source path"
        fi
        if [[ ! -d "$source_path" ]]; then
            die "Source directory not found: $source_path"
        fi
        print_info "Source: $source_path"
    else
        print_info "Source: GitHub ($GITHUB_REPO)"
    fi
    echo ""

    if [[ ! -d ".git" ]]; then
        print_warning "Current directory is not a git repository"
        if ! confirm "Install here anyway?"; then
            print_info "Installation cancelled"
            return 0
        fi
    fi

    ensure_dir ".claude"

    print_info "Installing core files..."
    local installed=0
    local skipped=0

    for entry in "${CORE_FILES[@]}"; do
        local src="${entry%%:*}"
        local filename="${entry##*:}"
        local dest=".claude/${filename}"

        if install_file "$source_mode" "$src" "$source_path" "$dest" "$filename"; then
            ((installed++)) || true
        else
            ((skipped++)) || true
        fi
    done

    if [[ -f ".claude/loop.sh" ]]; then
        chmod +x ".claude/loop.sh"
        print_step "Made loop.sh executable"
    fi

    if [[ "$install_mcp" == "true" ]]; then
        echo ""
        print_info "Installing MCP configuration..."
        local mcp_dest=".claude/${MCP_DEST}"

        if install_file "$source_mode" "$MCP_SOURCE" "$source_path" "$mcp_dest" "$MCP_DEST"; then
            ((installed++)) || true
        else
            ((skipped++)) || true
        fi
    fi

    echo ""
    print_header "Installation Complete"
    print_info "Installed: $installed files"
    [[ $skipped -gt 0 ]] && print_info "Skipped: $skipped files"

    # Run scan if requested
    if [[ "$run_scan" == "true" ]]; then
        echo ""
        do_scan "$scan_model"
    fi

    echo ""
    print_info "Next steps:"
    if [[ "$run_scan" != "true" ]]; then
        echo "  1. Run: ralph-install.sh scan (to generate CLAUDE.md)"
        echo "  2. Create specs/ directory with your requirement specs"
        echo "  3. Run: .claude/loop.sh plan"
    else
        echo "  1. Review generated CLAUDE.md and adjust as needed"
        echo "  2. Create specs/ directory with your requirement specs"
        echo "  3. Run: .claude/loop.sh plan"
    fi
}

# =============================================================================
# UNINSTALL
# =============================================================================

do_uninstall() {
    local keep_plan="${1:-false}"

    print_header "Uninstalling Ralph Wiggum Loop"
    echo ""

    if [[ ! -d ".claude" ]]; then
        print_warning "No .claude directory found"
        return 0
    fi

    if ! confirm "This will remove Ralph Wiggum files from .claude/. Continue?"; then
        print_info "Uninstall cancelled"
        return 0
    fi

    echo ""
    local removed=0

    print_info "Removing Ralph Wiggum files..."

    for entry in "${CORE_FILES[@]}"; do
        local filename="${entry##*:}"
        local target=".claude/${filename}"

        if [[ "$filename" == "IMPLEMENTATION_PLAN.md" && "$keep_plan" == "true" ]]; then
            print_step "Keeping: $target (user work)"
            continue
        fi

        if [[ -f "$target" ]]; then
            rm "$target"
            print_success "Removed: $target"
            ((removed++)) || true
        fi
    done

    if [[ -f ".claude/${MCP_DEST}" ]]; then
        echo ""
        if confirm "Remove MCP settings (.claude/${MCP_DEST})?"; then
            rm ".claude/${MCP_DEST}"
            print_success "Removed: .claude/${MCP_DEST}"
            ((removed++)) || true
        fi
    fi

    # Remove backup files if user wants
    local backups
    backups=$(find .claude -name "*.backup.*" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$backups" -gt 0 ]]; then
        echo ""
        if confirm "Remove $backups backup file(s)?"; then
            find .claude -name "*.backup.*" -delete 2>/dev/null || true
            print_success "Removed backup files"
        fi
    fi

    if [[ -d ".claude" ]] && [[ -z "$(ls -A .claude 2>/dev/null)" ]]; then
        rmdir ".claude"
        print_step "Removed empty .claude directory"
    fi

    echo ""
    print_header "Uninstall Complete"
    print_info "Removed: $removed files"
}

# =============================================================================
# SCAN
# =============================================================================

do_scan() {
    local model="${1:-opus}"
    local merge_mode="false"

    print_header "Scanning Project for CLAUDE.md"
    echo ""

    # Check prerequisites
    if ! command_exists claude; then
        die "Claude CLI not found. Install from: https://claude.ai/download"
    fi
    print_success "Claude CLI found"

    if [[ ! -d ".git" ]]; then
        print_warning "Not a git repository (continuing anyway)"
    fi

    # Handle existing CLAUDE.md
    if [[ -f "CLAUDE.md" ]]; then
        merge_mode="true"
        if ! handle_existing_file "CLAUDE.md"; then
            print_info "Scan cancelled"
            return 0
        fi
        print_info "Will merge with existing CLAUDE.md"
    fi

    print_info "Model: $model"
    print_info "Running deep codebase analysis..."
    echo ""

    # Build the scan prompt
    local scan_prompt
    scan_prompt=$(cat <<'SCAN_PROMPT_EOF'
Analyze this project and generate a CLAUDE.md file at the project root.

## Your Task

Scan the entire codebase to discover:

1. **Build & Run Commands**
   - Find package managers: package.json, Cargo.toml, go.mod, pyproject.toml, Makefile, CMakeLists.txt, build.gradle, composer.json, Gemfile, etc.
   - Identify build commands, dev servers, production builds
   - Note any special setup or prerequisites

2. **Validation Commands**
   - Test runners and exact commands (npm test, pytest, cargo test, go test, etc.)
   - Type checking commands (tsc, mypy, pyright, etc.)
   - Linters (eslint, ruff, golint, clippy, etc.)
   - Format checkers if present

3. **Codebase Patterns**
   - Directory structure and what lives where
   - Import/module patterns and conventions
   - Naming conventions (files, functions, classes)
   - Key abstractions, utilities, or shared code locations
   - Architecture patterns (MVC, clean architecture, etc.)

4. **Operational Notes**
   - Environment variables needed
   - Database or service dependencies
   - Common pitfalls from READMEs, comments, or docs
   - Development workflow hints

## Output Requirements

Write the file CLAUDE.md with these sections:

```markdown
# Project Name

Brief one-line description.

## Build & Run

[Commands to build and run the project]

## Validation

Run these after implementing to get feedback:

- Tests: `[exact test command]`
- Typecheck: `[exact typecheck command]`
- Lint: `[exact lint command]`

## Codebase Patterns

[Key patterns, directory structure, conventions]

## Operational Notes

[Environment setup, dependencies, pitfalls]
```

Keep it concise (60-100 lines). Operational and actionable, not verbose documentation.

IMPORTANT: Actually write the CLAUDE.md file using your file writing capabilities. Do not just output the content - create the file.
SCAN_PROMPT_EOF
)

    # Add merge context if existing file
    if [[ "$merge_mode" == "true" ]]; then
        local existing_content
        existing_content=$(cat "CLAUDE.md")
        scan_prompt="${scan_prompt}

## Existing CLAUDE.md to Merge

Preserve any manual additions or project-specific notes from the existing file while updating discovered information:

\`\`\`markdown
${existing_content}
\`\`\`
"
    fi

    # Run Claude headless
    if ! echo "$scan_prompt" | claude -p \
        --dangerously-skip-permissions \
        --model "$model" \
        --verbose; then
        die "Claude scan failed"
    fi

    echo ""

    # Validate output
    if [[ ! -f "CLAUDE.md" ]]; then
        die "CLAUDE.md was not created. Scan may have failed."
    fi

    print_header "Scan Complete"
    print_success "Generated: CLAUDE.md"
    echo ""
    print_info "Review the generated file and adjust as needed."
    print_info "CLAUDE.md is auto-loaded by Claude in every session."
}

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat << 'EOF'
Ralph Wiggum Loop Installer

USAGE:
    ralph-install.sh install [OPTIONS]
    ralph-install.sh scan [OPTIONS]
    ralph-install.sh uninstall [OPTIONS]
    ralph-install.sh --help | -h
    ralph-install.sh --version | -v

COMMANDS:
    install     Install Ralph Wiggum loop files to .claude/
    scan        Scan project and generate CLAUDE.md (auto-loaded by Claude)
    uninstall   Remove Ralph Wiggum files from .claude/

INSTALL OPTIONS:
    --from-git              Fetch files from GitHub (default)
    --from-local <path>     Copy files from local directory
    --with-mcp              Also install settings.local.json for MCP config
    --with-scan             Run scan after install to generate CLAUDE.md
    --model <opus|sonnet>   Model for scan (default: opus)
    -y, --yes               Non-interactive mode (auto-backup existing files)

SCAN OPTIONS:
    --model <opus|sonnet>   Model to use (default: opus)
    -y, --yes               Non-interactive mode (auto-backup existing files)

UNINSTALL OPTIONS:
    --keep-plan             Keep IMPLEMENTATION_PLAN.md (preserves your work)
    -y, --yes               Non-interactive mode

EXAMPLES:
    # Install from GitHub (default)
    ralph-install.sh install

    # Install and scan project in one step
    ralph-install.sh install --with-scan

    # Scan project to generate CLAUDE.md
    ralph-install.sh scan

    # Scan with faster/cheaper model
    ralph-install.sh scan --model sonnet

    # Install from local clone
    ralph-install.sh install --from-local ~/projects/ralph-playbook

    # Uninstall but keep your implementation plan
    ralph-install.sh uninstall --keep-plan

FILES:
    CLAUDE.md                    Project config (auto-loaded by Claude)
    .claude/loop.sh              Main loop script
    .claude/PROMPT_build.md      Building mode prompt
    .claude/PROMPT_plan.md       Planning mode prompt
    .claude/AGENTS.md            Reference template for CLAUDE.md structure
    .claude/IMPLEMENTATION_PLAN.md  Task list (generated by Ralph)

For more information, see: https://github.com/buker/ralph-playbook
EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    setup_colors

    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        install)
            local source_mode="git"
            local source_path=""
            local install_mcp="false"
            local run_scan="false"
            local scan_model="opus"
            ASSUME_YES="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --from-git)
                        source_mode="git"
                        shift
                        ;;
                    --from-local)
                        source_mode="local"
                        if [[ -z "${2:-}" ]]; then
                            die "--from-local requires a path argument"
                        fi
                        source_path="$2"
                        shift 2
                        ;;
                    --with-mcp)
                        install_mcp="true"
                        shift
                        ;;
                    --with-scan)
                        run_scan="true"
                        shift
                        ;;
                    --model)
                        if [[ -z "${2:-}" ]]; then
                            die "--model requires an argument (opus or sonnet)"
                        fi
                        scan_model="$2"
                        shift 2
                        ;;
                    -y|--yes)
                        ASSUME_YES="true"
                        shift
                        ;;
                    *)
                        die "Unknown install option: $1"
                        ;;
                esac
            done

            do_install "$source_mode" "$source_path" "$install_mcp" "$run_scan" "$scan_model"
            ;;

        uninstall)
            local keep_plan="false"
            ASSUME_YES="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --keep-plan)
                        keep_plan="true"
                        shift
                        ;;
                    -y|--yes)
                        ASSUME_YES="true"
                        shift
                        ;;
                    *)
                        die "Unknown uninstall option: $1"
                        ;;
                esac
            done

            do_uninstall "$keep_plan"
            ;;

        scan)
            local scan_model="opus"
            ASSUME_YES="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --model)
                        if [[ -z "${2:-}" ]]; then
                            die "--model requires an argument (opus or sonnet)"
                        fi
                        scan_model="$2"
                        shift 2
                        ;;
                    -y|--yes)
                        ASSUME_YES="true"
                        shift
                        ;;
                    *)
                        die "Unknown scan option: $1"
                        ;;
                esac
            done

            do_scan "$scan_model"
            ;;

        --help|-h)
            show_help
            ;;

        --version|-v)
            echo "ralph-install.sh version $SCRIPT_VERSION"
            ;;

        *)
            die "Unknown command: $command. Run 'ralph-install.sh --help' for usage."
            ;;
    esac
}

main "$@"
