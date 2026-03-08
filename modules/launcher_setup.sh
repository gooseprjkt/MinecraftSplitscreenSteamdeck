#!/bin/bash
# =============================================================================
# LAUNCHER SETUP MODULE - ElyPrismLauncher Edition
# =============================================================================
# @file        launcher_setup.sh
# @version     3.0.0-ely
# @date        2026-02-01
# @author      aradanmn (modified for ElyPrismLauncher by Kirill)
# @license     MIT
# @repository  https://github.com/aradanmn/MinecraftSplitscreenSteamdeck  
#
# @description
#   Handles ElyPrismLauncher detection, installation, and CLI verification.
#   ElyPrismLauncher is used for automated Minecraft instance creation via CLI,
#   providing reliable instance management and Fabric loader installation.
#
#   This is a drop-in replacement for the original PrismLauncher module.
#   All function names and exported variables remain the same for compatibility.
#
# @dependencies
#   - curl (for GitHub API queries)
#   - jq (for JSON parsing)
#   - wget (for downloading AppImage)
#   - flatpak (optional, for Flatpak installation)
#   - utilities.sh (for print_* functions)
#   - path_configuration.sh (for path constants, setters, and PREFER_FLATPAK)
#
# @exports
#   Functions:
#     - download_prism_launcher : Detect or install ElyPrismLauncher
#     - verify_prism_cli        : Verify CLI capabilities
#     - get_prism_executable    : Get executable path/command
#
#   Variables:
#     - PRISM_INSTALL_TYPE      : Installation type (appimage/flatpak)
#     - PRISM_EXECUTABLE        : Path or command to run ElyPrismLauncher
#
# @changelog
#   3.0.0-ely (2026-02-01) - Migrated to ElyPrismLauncher support
#   2.2.3 (2026-01-31) - Fix: Add --system flag to avoid flatpak remote selection prompt
#   2.2.2 (2026-01-25) - Fix: Try system-level Flatpak install first, then user-level
#   2.2.1 (2026-01-25) - Fix: Only create directories after successful download
#   2.2.0 (2026-01-25) - Use PREFER_FLATPAK from path_configuration
#   2.1.0 (2026-01-24) - Added Flatpak preference for immutable OS, arch detection
#   2.0.0 (2026-01-23) - Refactored to use centralized path configuration
#   1.0.0 (2026-01-22) - Initial version
# =============================================================================

# Module-level variables for tracking installation
PRISM_INSTALL_TYPE=""
PRISM_EXECUTABLE=""

# =============================================================================
# ElyPrismLauncher Configuration
# =============================================================================
# Flatpak configuration for ElyPrismLauncher
ELYPRISM_FLATPAK_ID="io.github.ElyPrismLauncher.ElyPrismLauncher"
ELYPRISM_FLATPAK_REMOTE_NAME="elyprismlauncher"
ELYPRISM_FLATPAK_REMOTE_URL="https://elyprismlauncher.github.io/flatpak/elyprismlauncher.flatpakref"

# GitHub repository for AppImage downloads
ELYPRISM_GITHUB_REPO="ElyPrismLauncher/ElyPrismLauncher"

# Specific AppImage URL (version 10.0.5) - fallback if API query fails
ELYPRISM_APPIMAGE_FALLBACK_URL="https://github.com/ElyPrismLauncher/ElyPrismLauncher/releases/download/10.0.5/ElyPrismLauncher-Linux-x86_64.AppImage"
ELYPRISM_APPIMAGE_FILENAME="ElyPrismLauncher-Linux-x86_64.AppImage"

# -----------------------------------------------------------------------------
# @function    download_prism_launcher
# @description Detects existing ElyPrismLauncher installation or installs it.
#              Uses different strategies based on the operating system.
#
#              NOTE: This function now installs ElyPrismLauncher instead of
#              PrismLauncher, but maintains the same interface for compatibility.
#
# @param       None
# @global      PREFER_FLATPAK         - (input) Whether to prefer Flatpak
# @global      PRISM_FLATPAK_DATA_DIR - (input) Flatpak data directory
# @global      PRISM_APPIMAGE_PATH    - (input/output) Expected AppImage location
# @global      PRISM_APPIMAGE_DATA_DIR - (input) AppImage data directory
# @return      0 on success, exits on critical failure
# -----------------------------------------------------------------------------
download_prism_launcher() {
    print_progress "Detecting ElyPrismLauncher installation..."

    local launcher_flatpak_id="${ELYPRISM_FLATPAK_ID}"

    # Priority 1: Check for existing Flatpak installation
    if is_flatpak_installed "$launcher_flatpak_id" 2>/dev/null; then
        print_success "Found existing ElyPrismLauncher Flatpak installation"
        mkdir -p "$PRISM_FLATPAK_DATA_DIR/instances"
        set_creation_launcher_prismlauncher "flatpak" "flatpak run $launcher_flatpak_id"
        print_info "   → Using Flatpak data directory: $PRISM_FLATPAK_DATA_DIR"
        return 0
    fi

    # Priority 2 (immutable OS only): Install Flatpak if preferred
    if [[ "$PREFER_FLATPAK" == true ]]; then
        print_info "Immutable OS detected - preferring Flatpak installation"

        if command -v flatpak &>/dev/null; then
            print_progress "Installing ElyPrismLauncher via Flatpak..."
            local flatpak_installed=false

            # Add custom ElyPrismLauncher remote if not exists (system)
            if ! flatpak remote-list --system 2>/dev/null | grep -q "$ELYPRISM_FLATPAK_REMOTE_NAME"; then
                print_progress "Adding ElyPrismLauncher Flatpak remote (system)..."
                flatpak remote-add --if-not-exists --system "$ELYPRISM_FLATPAK_REMOTE_NAME" "$ELYPRISM_FLATPAK_REMOTE_URL" 2>/dev/null || true
            fi

            # Try system-level install first (works on Bazzite/SteamOS)
            if flatpak install --system -y "$ELYPRISM_FLATPAK_REMOTE_NAME/$launcher_flatpak_id" 2>/dev/null; then
                flatpak_installed=true
                print_success "ElyPrismLauncher Flatpak installed (system)"
            else
                # Add remote for user if needed
                if ! flatpak remote-list --user 2>/dev/null | grep -q "$ELYPRISM_FLATPAK_REMOTE_NAME"; then
                    print_progress "Adding ElyPrismLauncher Flatpak remote (user)..."
                    flatpak remote-add --if-not-exists --user "$ELYPRISM_FLATPAK_REMOTE_NAME" "$ELYPRISM_FLATPAK_REMOTE_URL" 2>/dev/null || true
                fi
                # Fall back to user-level install
                if flatpak install --user -y "$ELYPRISM_FLATPAK_REMOTE_NAME/$launcher_flatpak_id" 2>/dev/null; then
                    flatpak_installed=true
                    print_success "ElyPrismLauncher Flatpak installed (user)"
                fi
            fi

            if [[ "$flatpak_installed" == true ]]; then
                mkdir -p "$PRISM_FLATPAK_DATA_DIR/instances"
                set_creation_launcher_prismlauncher "flatpak" "flatpak run $launcher_flatpak_id"
                print_info "   → Using Flatpak data directory: $PRISM_FLATPAK_DATA_DIR"
                return 0
            else
                print_warning "Flatpak installation failed - falling back to AppImage"
            fi
        else
            print_warning "Flatpak not available - falling back to AppImage"
        fi
    fi

    # Priority 3: Check for existing AppImage
    if [[ -f "$PRISM_APPIMAGE_PATH" ]]; then
        print_success "ElyPrismLauncher AppImage already present"
        set_creation_launcher_prismlauncher "appimage" "$PRISM_APPIMAGE_PATH"
        return 0
    fi

    # Priority 4: Download AppImage
    print_progress "No existing ElyPrismLauncher found - downloading AppImage..."

    # Try to get latest release from GitHub API, fallback to hardcoded URL
    local elyprism_url
    local arch
    arch=$(uname -m)
    
    # Query GitHub API for latest release
    elyprism_url=$(curl -s "https://api.github.com/repos/$ELYPRISM_GITHUB_REPO/releases/latest" | \
        jq -r --arg name "$ELYPRISM_APPIMAGE_FILENAME" '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
    
    # Fallback to hardcoded URL if API query fails
    if [[ -z "$elyprism_url" || "$elyprism_url" == "null" ]]; then
        print_info "Using fallback AppImage URL (version 10.0.5)"
        elyprism_url="$ELYPRISM_APPIMAGE_FALLBACK_URL"
    fi

    if [[ -z "$elyprism_url" || "$elyprism_url" == "null" ]]; then
        print_error "Could not find ElyPrismLauncher AppImage URL."
        print_error "Please check https://github.com/$ELYPRISM_GITHUB_REPO/releases manually."
        exit 1
    fi

    # Download to temp location first, only create directory on success
    local temp_appimage
    temp_appimage=$(mktemp)

    if ! wget -q -O "$temp_appimage" "$elyprism_url"; then
        print_error "Failed to download ElyPrismLauncher AppImage."
        rm -f "$temp_appimage" 2>/dev/null
        exit 1
    fi

    # Download successful - now create directory and move file
    mkdir -p "$PRISM_APPIMAGE_DATA_DIR"
    mv "$temp_appimage" "$PRISM_APPIMAGE_PATH"
    chmod +x "$PRISM_APPIMAGE_PATH"

    set_creation_launcher_prismlauncher "appimage" "$PRISM_APPIMAGE_PATH"
    print_success "ElyPrismLauncher AppImage downloaded successfully"
    print_info "   → Installation type: appimage"
}

# -----------------------------------------------------------------------------
# @function    verify_prism_cli
# @description Verifies that ElyPrismLauncher supports CLI operations.
#              Maintains same interface as original for compatibility.
#
# @param       None
# @global      CREATION_LAUNCHER_TYPE - (input) "appimage" or "flatpak"
# @global      CREATION_EXECUTABLE    - (input/output) May be updated if extracted
# @global      CREATION_DATA_DIR      - (input) Data directory for extraction
# @return      0 if CLI verified, 1 if CLI not available
# -----------------------------------------------------------------------------
verify_prism_cli() {
    print_progress "Verifying ElyPrismLauncher CLI capabilities..."

    local launcher_exec=""
    local help_output=""
    local exit_code=0
    local launcher_flatpak_id="${ELYPRISM_FLATPAK_ID}"

    if [[ "$CREATION_LAUNCHER_TYPE" == "flatpak" ]]; then
        launcher_exec="flatpak run $launcher_flatpak_id"
        print_info "   → Testing Flatpak CLI..."
        help_output=$($launcher_exec --help 2>&1)
        exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            print_warning "ElyPrismLauncher Flatpak CLI test failed"
            print_info "Error output: $(echo "$help_output" | head -3)"
            return 1
        fi
    else
        local appimage="$CREATION_EXECUTABLE"
        chmod +x "$appimage" 2>/dev/null || true
        help_output=$("$appimage" --help 2>&1)
        exit_code=$?

        if [[ $exit_code -ne 0 ]] && echo "$help_output" | grep -q -E "FUSE|Cannot mount|squashfs|Failed to open"; then
            print_warning "AppImage execution failed due to FUSE/squashfs issues"
            print_progress "Attempting to extract AppImage contents..."
            cd "$CREATION_DATA_DIR"
            local extracted_path="$CREATION_DATA_DIR/squashfs-root/AppRun"
            if "$appimage" --appimage-extract >/dev/null 2>&1; then
                if [[ -d "$CREATION_DATA_DIR/squashfs-root" ]] && [[ -x "$extracted_path" ]]; then
                    print_success "AppImage extracted successfully"
                    CREATION_EXECUTABLE="$extracted_path"
                    launcher_exec="$CREATION_EXECUTABLE"
                    help_output=$("$launcher_exec" --help 2>&1)
                    exit_code=$?
                else
                    print_warning "AppImage extraction failed or incomplete"
                    print_info "Will skip CLI creation and use manual instance creation method"
                    return 1
                fi
            else
                print_warning "AppImage extraction failed"
                print_info "Will skip CLI creation and use manual instance creation method"
                return 1
            fi
        fi
        launcher_exec="${PRISM_EXECUTABLE:-$appimage}"
    fi

    if [[ $exit_code -ne 0 ]]; then
        print_warning "ElyPrismLauncher execution failed, using manual instance creation"
        print_info "Error output: $(echo "$help_output" | head -3)"
        return 1
    fi

    if ! echo "$help_output" | grep -q -E "(cli|create|instance)"; then
        print_warning "ElyPrismLauncher CLI may not support instance creation. Checking with --help-all..."
        local extended_help=$($launcher_exec --help-all 2>&1)
        if ! echo "$extended_help" | grep -q -E "(cli|create-instance)"; then
            print_warning "This version of ElyPrismLauncher does not support CLI instance creation"
            print_info "Will use manual instance creation method instead"
            return 1
        fi
    fi

    print_info "Available ElyPrismLauncher CLI commands:"
    echo "$help_output" | grep -E "(create|instance|cli)" || echo "  (Basic CLI commands found)"
    print_success "ElyPrismLauncher CLI instance creation verified ($PRISM_INSTALL_TYPE)"
    return 0
}

# -----------------------------------------------------------------------------
# @function    get_prism_executable
# @description Returns the ElyPrismLauncher executable command or path.
#              Maintains same interface as original for compatibility.
#
# @param       None
# @global      CREATION_EXECUTABLE - (input) Executable path/command
# @stdout      Executable path or command
# @return      0 if executable set, 1 if not configured
# -----------------------------------------------------------------------------
get_prism_executable() {
    if [[ -n "$CREATION_EXECUTABLE" ]]; then
        echo "$CREATION_EXECUTABLE"
    else
        echo ""
        return 1
    fi
}
