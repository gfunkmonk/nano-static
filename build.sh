#!/bin/bash
# Build nano for various architectures using musl.cc cross-compilers
# Supports multiple architectures without requiring system-installed toolchains
# ENHANCED VERSION with parallel builds, caching, config bundling, and more!
set -e  # Exit on any error

# Configuration
WORKSPACE="${PWD}/build"
PATCHES="${PWD}/patches"
MAIN="${PWD}"
NCURSES_VERSION="${NCURSES_VERSION:-6.6}"
NANO_VERSION="${NANO_VERSION:-8.7}"
MUSL_CC_BASE="https://github.com/gfunkmonk/musl-cross/releases/download/02032026/"

# NEW: Cache configuration
CACHE_DIR="${WORKSPACE}/cache"
ENABLE_CACHE="${ENABLE_CACHE:-1}"

# NEW: Parallel build configuration
MAX_PARALLEL_BUILDS="${MAX_PARALLEL_BUILDS:-3}"
PARALLEL_MODE="${PARALLEL_MODE:-0}"

# NEW: Config bundling
BUNDLE_CONFIG="${BUNDLE_CONFIG:-0}"
NANORC_DIR="${NANORC_DIR:-${PWD}/nanorc}"

# Color definitions
NC="\033[0m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
BROWN="\033[0;33m"
TEAL="\033[2;36m"
BWHITE="\033[1;37m"
DKPURPLE="\033[0;35m"
WHITE="\033[0;37m"
LIME="\033[38;2;204;255;0m"
JUNEBUD="\033[38;2;189;218;87m"
CORAL="\033[38;2;255;127;80m"
PINK="\033[38;2;255;45;192m"
HOTPINK="\033[38;2;255;105;180m"
ORANGE="\033[38;2;255;165;0m"
PEACH="\033[38;2;246;161;146m"
GOLD="\033[38;2;255;215;0m"
NAVAJO="\033[38;2;255;222;173m"
LEMON="\033[38;2;255;244;79m"
CANARY="\033[38;2;255;255;153m"
KHAKI="\033[38;2;226;214;167m"
CRIMSON="\033[38;2;220;20;60m"
TAWNY="\033[38;2;204;78;0m"
ORCHID="\033[38;2;218;112;214m"
HELIOTROPE="\033[38;2;223;115;255m"
SLATE="\033[38;2;109;129;150m"
LAGOON="\033[38;2;142;235;236m"
PLUM="\033[38;2;142;69;133m"
VIOLET="\033[38;2;143;0;255m"
LIGHTROYAL="\033[38;2;10;148;255m"
TURQUOISE="\033[38;2;64;224;208m"
MINT="\033[38;2;152;255;152m"
AQUA="\033[38;2;18;254;202m"
SKY="\033[38;2;135;206;250m"
TOMATO="\033[38;2;255;99;71m"
CREAM="\033[38;2;255;253;208m"
REBECCA="\033[38;2;102;51;153m"
SELAGO="\033[38;2;255;215;255m"
CHARTREUSE="\033[38;2;127;255;0m"
BLOOD="$(tput setaf 88)"
MOSS="$(tput setaf 101)"
OCHRE="\033[38;2;204;119;34m"

# ============================================================================
# FEATURE 13: DEPENDENCY AUTO-DETECTION
# ============================================================================

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    local optional_deps=()
    
    echo -e "${CYAN}Checking build dependencies...${NC}"
    
    # Required dependencies
    local required=(
        "wget:wget"
        "tar:tar"
        "make:make"
        "gcc:gcc or build-essential"
        "patch:patch"
        "file:file"
    )
    
    for dep in "${required[@]}"; do
        IFS=':' read -r cmd desc <<< "$dep"
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$desc")
        else
            echo -e "  ${GREEN}✓${NC} $desc"
        fi
    done
    
    # Optional dependencies
    if ! command -v upx &> /dev/null; then
        optional_deps+=("upx (for binary compression)")
        echo -e "  ${YELLOW}○${NC} upx (optional - for compression)"
    else
        echo -e "  ${GREEN}✓${NC} upx (optional)"
    fi
    
    if ! command -v dialog &> /dev/null && [[ ${INTERACTIVE_MODE:-0} == 1 ]]; then
        optional_deps+=("dialog (for interactive mode)")
        echo -e "  ${YELLOW}○${NC} dialog (optional - for interactive menu)"
    fi
    
    # Report missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}Missing required dependencies:${NC}"
        for dep in "${missing_deps[@]}"; do
            echo -e "  ${RED}✗${NC} $dep"
        done
        echo ""
        echo -e "${YELLOW}Install them with:${NC}"
        
        if command -v apt-get &> /dev/null; then
            echo -e "  ${BWHITE}sudo apt-get install -y wget tar make gcc patch file build-essential${NC}"
        elif command -v yum &> /dev/null; then
            echo -e "  ${BWHITE}sudo yum install -y wget tar make gcc patch file${NC}"
        elif command -v pacman &> /dev/null; then
            echo -e "  ${BWHITE}sudo pacman -S wget tar make gcc patch file${NC}"
        else
            echo -e "  ${YELLOW}Please install using your system's package manager${NC}"
        fi
        
        return 1
    fi
    
    if [ ${#optional_deps[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Optional dependencies (recommended):${NC}"
        for dep in "${optional_deps[@]}"; do
            echo -e "  ${YELLOW}○${NC} $dep"
        done
    fi
    
    echo -e "${GREEN}All required dependencies satisfied!${NC}"
    echo ""
    return 0
}

# ============================================================================
# FEATURE 8: BUILD ARTIFACT CACHING
# ============================================================================

# Initialize cache directory
init_cache() {
    if [[ ${ENABLE_CACHE} == 1 ]]; then
        mkdir -p "${CACHE_DIR}/downloads"
        mkdir -p "${CACHE_DIR}/extracted"
        echo -e "${CYAN}Cache enabled at: ${CACHE_DIR}${NC}"
    fi
}

# Check if file exists in cache
check_cache() {
    local file=$1
    local cache_path="${CACHE_DIR}/downloads/${file}"
    
    if [[ ${ENABLE_CACHE} == 1 ]] && [[ -f "${cache_path}" ]]; then
        echo -e "${GREEN}Found in cache: ${file}${NC}"
        return 0
    fi
    return 1
}

# Add file to cache
add_to_cache() {
    local source=$1
    local filename=$2
    
    if [[ ${ENABLE_CACHE} == 1 ]]; then
        cp "${source}" "${CACHE_DIR}/downloads/${filename}"
        echo -e "${CYAN}Cached: ${filename}${NC}"
    fi
}

# Download with cache support
cached_download() {
    local url=$1
    local output=$2
    local filename=$(basename "$output")
    
    if check_cache "${filename}"; then
        cp "${CACHE_DIR}/downloads/${filename}" "${output}"
        return 0
    fi
    
    echo -e "${TAWNY}Downloading ${filename}...${NC}"
    if wget -q --show-progress --tries=3 --timeout=30 "${url}" -O "${output}"; then
        add_to_cache "${output}" "${filename}"
        return 0
    fi
    return 1
}

# Clear cache
clear_cache() {
    if [[ -d "${CACHE_DIR}" ]]; then
        echo -e "${YELLOW}Clearing cache...${NC}"
        rm -rf "${CACHE_DIR}"
        echo -e "${GREEN}Cache cleared${NC}"
    fi
}

# ============================================================================
# FEATURE 7: CUSTOM NANO CONFIG BUNDLING
# ============================================================================

# Bundle nanorc configuration files
bundle_nanorc() {
    local arch=$1
    local output_dir=$2
    
    if [[ ${BUNDLE_CONFIG} == 1 ]]; then
        if [[ -d "${NANORC_DIR}" ]]; then
            echo -e "${PINK}Bundling nanorc configuration...${NC}"
            local config_bundle="${output_dir}/nano-${NANO_VERSION}-${arch}-config.tar.gz"
            
            tar -czf "${config_bundle}" -C "${NANORC_DIR}" . 2>/dev/null || {
                echo -e "${YELLOW}Warning: Could not bundle config files${NC}"
                return 1
            }
            
            echo -e "${GREEN}Config bundled: ${config_bundle}${NC}"
            
            # Create installation instructions
            cat > "${output_dir}/nano-${arch}-INSTALL.txt" << EOF
Installation Instructions for nano ${NANO_VERSION} (${arch})
================================================================

1. Copy the binary:
   cp nano-${NANO_VERSION}-${arch} /usr/local/bin/nano
   chmod +x /usr/local/bin/nano

2. Extract configuration (optional):
   mkdir -p ~/.config/nano
   tar -xzf nano-${NANO_VERSION}-${arch}-config.tar.gz -C ~/.config/nano/

3. Set terminal:
   export TERM=linux
   # Add to ~/.bashrc for permanent setting

4. Test:
   nano --version

If you get 'Error opening terminal', run: export TERM=linux
EOF
            echo -e "${CYAN}Created installation instructions${NC}"
        else
            echo -e "${YELLOW}No nanorc directory found at ${NANORC_DIR}${NC}"
        fi
    fi
}

# Create default nanorc if not exists
create_default_nanorc() {
    if [[ ! -d "${NANORC_DIR}" ]]; then
        echo -e "${CYAN}Creating default nanorc configuration...${NC}"
        mkdir -p "${NANORC_DIR}"
        
        cat > "${NANORC_DIR}/nanorc" << 'EOF'
# Nano configuration for embedded/minimal systems

# Enable mouse support
set mouse

# Smooth scrolling
set smooth

# Auto-indent
set autoindent

# Line numbers
set linenumbers

# Tab size
set tabsize 4

# Convert tabs to spaces
set tabstospaces

# Enable soft word wrapping
set softwrap

# Syntax highlighting
include "/usr/share/nano/*.nanorc"
EOF
        echo -e "${GREEN}Created default nanorc${NC}"
    fi
}

# ============================================================================
# FEATURE 6: PARALLEL ARCHITECTURE BUILDS
# ============================================================================

# Build queue for parallel execution
declare -a BUILD_QUEUE=()
declare -a RUNNING_BUILDS=()
declare -A BUILD_PIDS=()

# Add build to queue
queue_build() {
    local display_name=$1
    local toolchain_prefix=$2
    local musl_name=$3
    BUILD_QUEUE+=("${display_name}:${toolchain_prefix}:${musl_name}")
}

# Execute build in background
execute_build_parallel() {
    local display_name=$1
    local toolchain_prefix=$2
    local musl_name=$3
    local log_file="${WORKSPACE}/logs/build-${display_name}.log"
    
    mkdir -p "${WORKSPACE}/logs"
    
    # Run build in background, redirecting output to log
    (
        build_for_arch "$display_name" "$toolchain_prefix" "$musl_name" > "${log_file}" 2>&1
        echo $? > "${WORKSPACE}/logs/build-${display_name}.status"
    ) &
    
    local pid=$!
    BUILD_PIDS["${display_name}"]=$pid
    RUNNING_BUILDS+=("${display_name}")
    
    echo -e "${CYAN}Started build for ${display_name} (PID: ${pid})${NC}"
}

# Wait for a build slot to become available
wait_for_slot() {
    while [[ ${#RUNNING_BUILDS[@]} -ge ${MAX_PARALLEL_BUILDS} ]]; do
        # Check which builds have completed
        for i in "${!RUNNING_BUILDS[@]}"; do
            local arch="${RUNNING_BUILDS[$i]}"
            local pid="${BUILD_PIDS[$arch]}"
            
            if ! kill -0 "$pid" 2>/dev/null; then
                # Build completed
                wait "$pid" || true
                
                # Check status
                local status_file="${WORKSPACE}/logs/build-${arch}.status"
                if [[ -f "${status_file}" ]] && [[ $(cat "${status_file}") == "0" ]]; then
                    echo -e "${GREEN}✓ Completed: ${arch}${NC}"
                else
                    echo -e "${RED}✗ Failed: ${arch}${NC}"
                    echo -e "${YELLOW}  See log: ${WORKSPACE}/logs/build-${arch}.log${NC}"
                fi
                
                # Remove from running builds
                unset 'RUNNING_BUILDS[i]'
                RUNNING_BUILDS=("${RUNNING_BUILDS[@]}")  # Re-index array
                break
            fi
        done
        
        sleep 1
    done
}

# Process build queue
process_build_queue() {
    echo -e "${VIOLET}Processing build queue with up to ${MAX_PARALLEL_BUILDS} parallel builds...${NC}"
    
    for item in "${BUILD_QUEUE[@]}"; do
        IFS=':' read -r display_name toolchain_prefix musl_name <<< "$item"
        
        wait_for_slot
        execute_build_parallel "$display_name" "$toolchain_prefix" "$musl_name"
    done
    
    # Wait for all remaining builds
    echo -e "${CYAN}Waiting for remaining builds to complete...${NC}"
    for arch in "${RUNNING_BUILDS[@]}"; do
        local pid="${BUILD_PIDS[$arch]}"
        wait "$pid" || true
        
        local status_file="${WORKSPACE}/logs/build-${arch}.status"
        if [[ -f "${status_file}" ]] && [[ $(cat "${status_file}") == "0" ]]; then
            echo -e "${GREEN}✓ Completed: ${arch}${NC}"
        else
            echo -e "${RED}✗ Failed: ${arch}${NC}"
        fi
    done
}

# ============================================================================
# FEATURE 14: INTERACTIVE MENU MODE
# ============================================================================

# Interactive architecture selection using dialog
interactive_menu() {
    if ! command -v dialog &> /dev/null; then
        echo -e "${RED}Error: 'dialog' command not found. Install it for interactive mode.${NC}"
        echo -e "${YELLOW}Install with: sudo apt-get install dialog${NC}"
        return 1
    fi
    
    # Build architecture list for dialog
    local options=()
    local i=1
    for arch in "${ARCHITECTURES[@]}"; do
        IFS=':' read -r display_name _ _ <<< "$arch"
        options+=("$i" "$display_name" "off")
        ((i++))
    done
    
    # Architecture selection
    local selected=$(dialog --stdout --checklist \
        "Select architectures to build:" 20 60 15 \
        "${options[@]}")
    
    if [[ -z "$selected" ]]; then
        echo -e "${YELLOW}No architectures selected${NC}"
        return 1
    fi
    
    # Version selection
    local nano_ver=$(dialog --stdout --inputbox \
        "Nano version:" 8 40 "${NANO_VERSION}")
    [[ -n "$nano_ver" ]] && NANO_VERSION="$nano_ver"
    
    local ncurses_ver=$(dialog --stdout --inputbox \
        "Ncurses version:" 8 40 "${NCURSES_VERSION}")
    [[ -n "$ncurses_ver" ]] && NCURSES_VERSION="$ncurses_ver"
    
    # Build options
    local build_opts=$(dialog --stdout --checklist \
        "Build options:" 15 50 6 \
        1 "Parallel builds" off \
        2 "Bundle nanorc config" off \
        3 "Skip UPX compression" off \
        4 "Enable caching" on)
    
    if echo "$build_opts" | grep -q "1"; then
        PARALLEL_MODE=1
        MAX_PARALLEL_BUILDS=$(dialog --stdout --inputbox \
            "Max parallel builds:" 8 40 "3")
    fi
    
    if echo "$build_opts" | grep -q "2"; then
        BUNDLE_CONFIG=1
    fi
    
    if echo "$build_opts" | grep -q "3"; then
        NO_UPX=1
    fi
    
    if ! echo "$build_opts" | grep -q "4"; then
        ENABLE_CACHE=0
    fi
    
    # Convert selections to architecture names
    SELECTED_ARCHS=()
    for num in $selected; do
        local idx=$((num - 1))
        IFS=':' read -r display_name _ _ <<< "${ARCHITECTURES[$idx]}"
        SELECTED_ARCHS+=("$display_name")
    done
    
    clear
    echo -e "${GREEN}Selected architectures: ${SELECTED_ARCHS[*]}${NC}"
    echo -e "${CYAN}Nano version: ${NANO_VERSION}${NC}"
    echo -e "${CYAN}Ncurses version: ${NCURSES_VERSION}${NC}"
    echo ""
    
    return 0
}

# ============================================================================
# FEATURE 9: GITHUB ACTIONS/CI INTEGRATION
# ============================================================================

# Generate GitHub Actions workflow
generate_github_workflow() {
    local workflow_file=".github/workflows/build-nano.yml"
    
    echo -e "${CYAN}Generating GitHub Actions workflow...${NC}"
    mkdir -p .github/workflows
    
    cat > "${workflow_file}" << 'EOF'
name: Build Nano Cross-Platform

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:
    inputs:
      nano_version:
        description: 'Nano version to build'
        required: true
        default: '8.7'
      ncurses_version:
        description: 'Ncurses version to build'
        required: true
        default: '6.6'

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        arch: 
          - aarch64
          - armv7
          - x86_64
          - mips
          - mipsel
          - riscv64
      fail-fast: false
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y wget build-essential texinfo file upx-ucl
    
    - name: Set versions
      run: |
        echo "NANO_VERSION=${{ github.event.inputs.nano_version || '8.7' }}" >> $GITHUB_ENV
        echo "NCURSES_VERSION=${{ github.event.inputs.ncurses_version || '6.6' }}" >> $GITHUB_ENV
    
    - name: Build nano for ${{ matrix.arch }}
      run: |
        chmod +x build_nano_enhanced.sh
        ./build_nano_enhanced.sh ${{ matrix.arch }}
    
    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: nano-${{ matrix.arch }}
        path: output/nano-*-${{ matrix.arch }}*
        retention-days: 30
  
  release:
    needs: build
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/')
    
    steps:
    - name: Download all artifacts
      uses: actions/download-artifact@v3
      with:
        path: artifacts
    
    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: artifacts/**/*
        draft: false
        prerelease: false
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF
    
    echo -e "${GREEN}Created GitHub workflow: ${workflow_file}${NC}"
    echo ""
    echo -e "${YELLOW}To use this workflow:${NC}"
    echo -e "  1. Commit the .github directory to your repository"
    echo -e "  2. Push to GitHub"
    echo -e "  3. Go to Actions tab to see builds"
    echo -e "  4. Create a tag (e.g., v8.7) to trigger a release"
    echo ""
}

# ============================================================================
# ORIGINAL FUNCTIONS (with cache integration)
# ============================================================================

# Normalize architecture names
normalize_arch() {
    local raw_arch=$1
    case "$raw_arch" in
        arm64|armv8) echo "aarch64" ;;
        armv6l) echo "armv6" ;;
        armv7l) echo "armv7" ;;
        i386|x32) echo "i686" ;;
        openrisc) echo "or1k" ;;
        ppc) echo "powerpc" ;;
        ppcle) echo "powerpcle" ;;
        ppc64) echo "powerpc64" ;;
        ppc64le) echo "powerpc64le" ;;
        risc|risc32) echo "riscv32" ;;
        risc64) echo "riscv64" ;;
        sh) echo "sh4" ;;
        x86-64|amd64|x64) echo "x86_64" ;;
        *) echo "$raw_arch" ;;
    esac
}

# Get per-architecture default CFLAGS
get_arch_cflags() {
    local arch=$1
    case "$arch" in
        aarch64) echo "-march=armv8-a" ;;
        armv5) echo "-march=armv5te -mtune=arm946e-s -mfloat-abi=soft" ;;
        armv6) echo "-march=armv6 -mfloat-abi=hard -mfpu=vfp" ;;
        armv7) echo "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
        i686) echo "-march=i686 -mtune=generic" ;;
        loongarch64) echo "-march=loongarch64" ;;
        m68k) echo "-march=68020 -ffreestanding" ;;
        mips64) echo "-march=mips64 -mabi=64" ;;
        mips64el) echo "-mplt" ;;
        powerpc) echo "-mpowerpc -m32" ;;
        powerpcle) echo "-m32" ;;
        powerpc64) echo "-mpowerpc64 -m64 -falign-functions=32 -falign-labels=32 -falign-loops=32 -falign-jumps=32" ;;
        powerpc64le) echo "-m64" ;;
        riscv64) echo "-march=rv64gc -mabi=lp64d" ;;
        riscv32) echo "-ffreestanding -Wno-implicit-function-declaration -Wno-int-conversion" ;;
        x86_64) echo "-march=x86-64 -mtune=generic" ;;
        *) echo "" ;;
    esac
}

# Determine nano download URL based on version
get_nano_url() {
    local version=$1
    local major_version="${version%%.*}"

    if [[ "$major_version" == "8" ]]; then
        echo "https://www.nano-editor.org/dist/v8/nano-${version}.tar.xz"
    elif [[ "$major_version" == "7" ]]; then
        echo "https://www.nano-editor.org/dist/v7/nano-${version}.tar.xz"
    elif [[ "$major_version" == "6" ]]; then
        echo "https://www.nano-editor.org/dist/v6/nano-${version}.tar.xz"
    else
        echo "https://www.nano-editor.org/dist/latest/nano-${version}.tar.xz"
    fi
}

# Available architectures from musl.cc
ARCHITECTURES=(
    "armv5:armv5-unknown-linux-musleabi:armv5-unknown-linux-musleabi"
    "armv6:armv6-unknown-linux-musleabihf:armv6-unknown-linux-musleabihf"
    "armv7:armv7-unknown-linux-musleabihf:armv7-unknown-linux-musleabihf"
    "aarch64:aarch64-unknown-linux-musl:aarch64-unknown-linux-musl"
    "i486:i486-unknown-linux-musl:i486-unknown-linux-musl"
    "i586:i586-unknown-linux-musl:i586-unknown-linux-musl"
    "i686:i686-unknown-linux-musl:i686-unknown-linux-musl"
    "loongarch64:loongarch64-unknown-linux-musl:loongarch64-unknown-linux-musl"
    "m68k:m68k-unknown-linux-musl:m68k-unknown-linux-musl"
    "mips:mips-unknown-linux-muslsf:mips-unknown-linux-muslsf"
    "mips64:mips64-unknown-linux-musl:mips64-unknown-linux-musl"
    "mipsel:mipsel-unknown-linux-muslsf:mipsel-unknown-linux-muslsf"
    "mips64el:mips64el-unknown-linux-musl:mips64el-unknown-linux-musl"
    "or1k:or1k-unknown-linux-musl:or1k-unknown-linux-musl"
    "powerpc:powerpc-unknown-linux-muslsf:powerpc-unknown-linux-muslsf"
    "powerpc64:powerpc64-unknown-linux-musl:powerpc64-unknown-linux-musl"
    "powerpcle:powerpcle-unknown-linux-muslsf:powerpcle-unknown-linux-muslsf"
    "powerpc64le:powerpc64le-unknown-linux-musl:powerpc64le-unknown-linux-musl"
    "riscv32:riscv32-unknown-linux-musl:riscv32-unknown-linux-musl"
    "riscv64:riscv64-unknown-linux-musl:riscv64-unknown-linux-musl"
    "s390x:s390x-ibm-linux-musl:s390x-ibm-linux-musl"
    "sh4:sh4-multilib-linux-musl:sh4-multilib-linux-musl"
    "x86_64:x86_64-unknown-linux-musl:x86_64-unknown-linux-musl"
)

# Function to display usage
usage() {
    echo -e "${CANARY}Usage: $0 [architecture] [options]${NC}"
    echo ""
    echo -e "${VIOLET}Options:${NC}"
    echo -e "  ${PINK}--nano-ver VERSION${NC}       ${SLATE}Set nano version (default: ${NANO_VERSION})${NC}"
    echo -e "  ${PINK}--ncurses-ver VERSION${NC}    ${SLATE}Set ncurses version (default: ${NCURSES_VERSION})${NC}"
    echo -e "  ${PINK}--help, -h, help${NC}         ${SLATE}Show this help message${NC}"
    echo -e "  ${PINK}--clean, clean${NC}           ${SLATE}Cleans build dir (except toolchains)${NC}"
    echo -e "  ${PINK}--clean-all, clean-all${NC}   ${SLATE}Cleans build dir completely${NC}"
    echo -e "  ${PINK}--inst-dep, inst-dep${NC}     ${SLATE}Tries to install build dependancies${NC}"
    echo -e "  ${PINK}--njobs NUMBER${NC}           ${SLATE}Number of parallel jobs (default: auto)${NC}"
    echo -e "  ${PINK}--extra-cflags 'VALUE'${NC}   ${SLATE}Extra CFLAGS to append to default${NC}"
    echo -e "  ${PINK}--no-upx${NC}                 ${SLATE}Skip UPX compression${NC}"
    echo ""
    echo -e "${GREEN}NEW FEATURES:${NC}"
    echo -e "  ${PINK}--parallel [NUM]${NC}         ${SLATE}Build multiple architectures in parallel (default: 3)${NC}"
    echo -e "  ${PINK}--bundle-config${NC}          ${SLATE}Bundle nanorc configuration with binaries${NC}"
    echo -e "  ${PINK}--no-cache${NC}               ${SLATE}Disable caching of downloads${NC}"
    echo -e "  ${PINK}--clear-cache${NC}            ${SLATE}Clear the download cache${NC}"
    echo -e "  ${PINK}--interactive, -i${NC}        ${SLATE}Interactive menu mode (requires dialog)${NC}"
    echo -e "  ${PINK}--generate-ci${NC}            ${SLATE}Generate GitHub Actions workflow${NC}"
    echo -e "  ${PINK}--check-deps${NC}             ${SLATE}Check for missing dependencies${NC}"
    echo ""
    echo -e "${LIGHTROYAL}Available architectures:${NC}"
    for arch in "${ARCHITECTURES[@]}"; do
        IFS=':' read -r display_name toolchain musl_name <<< "$arch"
        echo -e "  ${BLUE}•${NC} ${ORANGE}$display_name${NC}"
    done
    echo ""
    echo -e "${CREAM}Examples:${NC}"
    echo -e "${BWHITE}  $0 mipsel${NC}                                     ${TEAL}# Build for mipsel${NC}"
    echo -e "${BWHITE}  $0 --parallel 5${NC}                               ${TEAL}# Build all archs in parallel${NC}"
    echo -e "${BWHITE}  $0 --bundle-config aarch64${NC}                    ${TEAL}# Build with config bundle${NC}"
    echo -e "${BWHITE}  $0 --interactive${NC}                              ${TEAL}# Interactive menu mode${NC}"
    echo -e "${BWHITE}  $0 --generate-ci${NC}                              ${TEAL}# Generate CI workflow${NC}"
    exit 1
}

# Function to clean
cleanup() {
    read -p "Are you sure you want to continue? (y/n): " -n 1 confirmation
    echo ""
    
    if [[ "$confirmation" != 'y' && "$confirmation" != 'Y' ]]; then
        echo "Operation cancelled."
        exit 1
    fi
    
    echo "Removing build directory..."
    rm -fr "${WORKSPACE}"/build*/
    rm -fr "${WORKSPACE}"/sysroot*/
    rm -fr "${WORKSPACE}"/logs/
    
    return 0
}

# Function to clean all
cleanall() {
    read -p "Are you sure you want to continue? (y/n): " -n 1 confirmation
    echo ""
    
    if [[ "$confirmation" != 'y' && "$confirmation" != 'Y' ]]; then
        echo "Operation cancelled."
        exit 1
    fi
    
    echo "Removing build directory..."
    rm -fr "${WORKSPACE}"
    
    return 0
}

# Install basic build dependencies
installdep() {
    echo -e "${ORANGE}Installing build dependencies...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1
        apt-get install -y wget build-essential texinfo file dialog upx-ucl > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y wget gcc make texinfo file dialog upx > /dev/null 2>&1
    else
        echo -e "${LEMON}Warning: Could not detect package manager.${NC}"
    fi
    exit 1
}

# Parallel patch application
apply_patches_parallel() {
    local patch_dir=$1
    local target_dir=$2
    local patch_pattern=$3

    if [[ ! -d "$patch_dir" ]]; then
        return 0
    fi

    shopt -s nullglob
    local patches=()
    while IFS= read -r -d '' patch; do
        patches+=("$patch")
    done < <(find "$patch_dir" -maxdepth 1 -name "$patch_pattern" -type f -print0 | sort -z)

    if [[ ${#patches[@]} -eq 0 ]]; then
        return 0
    fi

    local display_dir="${patch_dir#$PATCHES/}"
    echo -e "${HELIOTROPE}= Applying patches from ${display_dir}${NC}"

    for patch in "${patches[@]}"; do
        echo -e "${PEACH}Applying ${patch##*/}${NC}"
        local abs_patch=$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")
        pushd "$target_dir" >/dev/null
        patch -sp1 --fuzz=4 < "${abs_patch}" || {
            echo -e "${LEMON}WARNING: Failed to apply patch ${patch##*/}${NC}" >&2
        }
        popd >/dev/null
    done
}

# Get number of parallel jobs
get_parallel_jobs() {
    if [[ -n ${NJOBS:-} ]]; then
        echo "$NJOBS"
    elif command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.physicalcpu
    else
        echo "1"
    fi
}

# Function to download and extract toolchain (with caching)
setup_toolchain() {
    local musl_name=$1
    local toolchain_dir="${WORKSPACE}/toolchains/${musl_name}"

    if [ -d "${toolchain_dir}" ]; then
        echo -e "${LEMON}Toolchain ${musl_name} already exists, skipping download...${NC}"
        return 0
    fi

    echo -e "${TAWNY}Setting up ${musl_name} toolchain...${NC}"
    mkdir -p "${WORKSPACE}/toolchains"
    cd "${WORKSPACE}/toolchains"

    local archive="${musl_name}.tar.xz"
    
    # Use cached download
    if ! cached_download "${MUSL_CC_BASE}/${archive}" "${archive}"; then
        echo -e "${TOMATO}Error: Failed to download toolchain ${musl_name}${NC}"
        return 1
    fi

    echo -e "${LAGOON}Extracting toolchain...${NC}"
    tar -xf "${archive}"

    echo -e "${KHAKI}Toolchain ready at ${toolchain_dir}${NC}"
    rm -f "${archive}"
}

# Function to build for a specific architecture
build_for_arch() {
    local display_name=$1
    local toolchain_prefix=$2
    local musl_name=$3

    echo ""
    echo -e "${BWHITE}==========================================${NC}"
    echo -e "${TURQUOISE}Building nano for ${display_name}${NC}"
    echo -e "${BWHITE}==========================================${NC}"

    local norm_arch=$(normalize_arch "$display_name")
    local arch_cflags=$(get_arch_cflags "$norm_arch")

    if [[ -n ${EXTRA_CFLAGS:-} ]]; then
       local BUILD_CFLAGS="-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer ${arch_cflags} ${EXTRA_CFLAGS}"
    else
       local BUILD_CFLAGS="-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer ${arch_cflags}"
    fi
    local BUILD_LDFLAGS="-Wl,--gc-sections"

    setup_toolchain "${musl_name}" || return 1

    local TOOLCHAIN_DIR="${WORKSPACE}/toolchains/${musl_name}"
    local SYSROOT="${WORKSPACE}/sysroot-${display_name}"
    local BUILD_DIR="${WORKSPACE}/build-${display_name}"

    export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"

    if ! command -v "${toolchain_prefix}"-gcc &> /dev/null; then
        echo -e "${TOMATO}Error: ${toolchain_prefix}-gcc not found in PATH${NC}"
        return 1
    fi

    mkdir -p "${BUILD_DIR}"
    mkdir -p "${SYSROOT}"

    # Build ncurses
    echo -e "${LIGHTROYAL}Building ncurses ${NCURSES_VERSION} for ${display_name}...${NC}"
    cd "${BUILD_DIR}"

    cached_download "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" \
                     "ncurses-${NCURSES_VERSION}.tar.gz" || {
        echo -e "${TOMATO}Error: Failed to download ncurses ${NCURSES_VERSION}${NC}"
        return 1
    }

    rm -rf "ncurses-${NCURSES_VERSION}"
    tar -xzf "ncurses-${NCURSES_VERSION}.tar.gz"
    cd "ncurses-${NCURSES_VERSION}"

    echo -e "\n"
    apply_patches_parallel "$PATCHES/ncurses" "$BUILD_DIR/ncurses-${NCURSES_VERSION}" "${NCURSES_VERSION}*.patch"
    echo -e "\n"
    sleep 1

    CFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="${BUILD_LDFLAGS}" \
    ./configure \
        --host="${toolchain_prefix}" \
        --prefix="${SYSROOT}" \
        --enable-static \
        --disable-shared \
        --without-debug \
        --without-tests \
        --without-cxx-binding \
        --with-normal \
        --with-ticlib \
        --with-termlib \
        --disable-stripping \
        --disable-widec \
        --with-fallbacks=linux,screen,vt100,xterm,xterm-256color \
        CC="${toolchain_prefix}"-gcc \
        STRIP="${toolchain_prefix}"-strip

    make -j"$(get_parallel_jobs)" -s
    make install -s

    echo -e "${TEAL}Fixing ncurses header paths...${NC}"
    cd "${SYSROOT}/include"
    if [ -d "ncurses" ]; then
        cd ncurses
        mkdir -p ncurses
        for f in *.h; do
            [ -f "$f" ] && ln -sf ../"$f" ncurses/"$f"
        done
    fi

    # Build nano
    echo -e "${PEACH}Building nano ${NANO_VERSION} for ${display_name}...${NC}"
    cd "${BUILD_DIR}"

    local NANO_URL=$(get_nano_url "${NANO_VERSION}")
    cached_download "${NANO_URL}" "nano-${NANO_VERSION}.tar.xz" || {
        echo -e "${TOMATO}Error: Failed to download nano ${NANO_VERSION}${NC}"
        echo -e "${LEMON}Tried URL: ${NANO_URL}${NC}"
        return 1
    }

    rm -rf "nano-${NANO_VERSION}"
    tar -xf "nano-${NANO_VERSION}.tar.xz"
    cd "nano-${NANO_VERSION}"

    echo -e "\n"
    apply_patches_parallel "$PATCHES/nano" "$BUILD_DIR/nano-${NANO_VERSION}" "nano-*.patch"
    echo -e "\n"

    if [[ $(echo "${NANO_VERSION} < 8.0" | bc) == 1 ]]; then
       echo -e "\n"
       apply_patches_parallel "$PATCHES/nano" "$BUILD_DIR/nano-${NANO_VERSION}" "nano7-*.patch"
       echo -e "\n"
    fi

    sleep 1

    CFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="${BUILD_LDFLAGS}" \
    PKG_CONFIG_PATH="${SYSROOT}/lib/pkgconfig" \
    ./configure \
        --host="${toolchain_prefix}" \
        --prefix=/usr/local \
        --sysconfdir=/etc \
        --disable-nls \
        --disable-utf8 \
        --enable-tiny \
        --enable-nanorc \
        --enable-color \
        --enable-extra \
        --enable-largefile \
        --enable-libmagic \
        CC="${toolchain_prefix}"-gcc \
        CPPFLAGS="-I${SYSROOT}/include/ncurses -I${SYSROOT}/include" \
        LDFLAGS="-L${SYSROOT}/lib ${BUILD_LDFLAGS}"

    make -j"$(get_parallel_jobs)" -s

    export OUTPUT_DIR="${MAIN}/output"
    mkdir -p "${OUTPUT_DIR}"

    echo -e "${AQUA}Stripping binary...${NC}"
    "${toolchain_prefix}"-strip src/nano -o "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}"

    if [[ ! ${NO_UPX:-} ]] && command -v upx >/dev/null 2>&1; then
        echo -e "${PEACH}Compressing with UPX...${NC}"
        upx --ultra-brute "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" > /dev/null 2>&1 || {
            echo -e "${LEMON}UPX compression failed, continuing...${NC}"
        }
    elif [[ ${NO_UPX:-} ]]; then
        echo -e "${JUNEBUD}UPX compression disabled...${NC}"
    fi

    # Bundle configuration if requested
    bundle_nanorc "${display_name}" "${OUTPUT_DIR}"

    echo -e "${MINT}✓ Build complete for ${display_name}!${NC}"
    echo -e "${HELIOTROPE}Binary: ${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}${NC}"

    local file_info=$(file "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" | cut -d: -f2-)
    local size_info=$(du -h "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" 2>/dev/null | cut -f1)

    echo -e "${NAVAJO}Type: ${file_info}${NC}"
    echo -e "${SKY}Size: ${size_info}${NC}"
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# Parse command line arguments
TARGET_ARCH=""
SELECTED_ARCHS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --nano-ver)
            NANO_VERSION="$2"
            shift 2
            ;;
        --ncurses-ver)
            NCURSES_VERSION="$2"
            shift 2
            ;;
        -h|--help|help)
            usage
            ;;
        --clean|clean)
            cleanup
            exit 0
            ;;
        --clean-all|clean-all)
            cleanall
            exit 0
            ;;
        --inst-dep|inst-dep)
            installdep
            ;;
        --check-deps)
            check_dependencies
            exit $?
            ;;
        --clear-cache)
            clear_cache
            exit 0
            ;;
        --generate-ci)
            generate_github_workflow
            exit 0
            ;;
        --parallel)
            PARALLEL_MODE=1
            if [[ -n ${2:-} ]] && [[ $2 =~ ^[0-9]+$ ]]; then
                MAX_PARALLEL_BUILDS=$2
                shift 2
            else
                shift
            fi
            ;;
        --parallel=*)
            PARALLEL_MODE=1
            MAX_PARALLEL_BUILDS=${1#*=}
            shift
            ;;
        --bundle-config)
            BUNDLE_CONFIG=1
            shift
            ;;
        --no-cache)
            ENABLE_CACHE=0
            shift
            ;;
        -i|--interactive)
            INTERACTIVE_MODE=1
            shift
            ;;
        --extra-cflags)
            EXTRA_CFLAGS=${2:-}
            [[ -z ${EXTRA_CFLAGS} ]] && { echo -e "${RED}ERROR: --extra-cflags requires a value${NC}" >&2; exit 1; }
            export EXTRA_CFLAGS
            shift 2
            ;;
        --extra-cflags=*)
            export EXTRA_CFLAGS=${1#*=}
            shift
            ;;
        --njobs)
            NJOBS=${2:-}
            [[ -z ${NJOBS} ]] && { echo -e "${RED}ERROR: --njobs requires a value${NC}" >&2; exit 1; }
            export NJOBS
            shift 2
            ;;
        --njobs=*)
            export NJOBS=${1#*=}
            shift
            ;;
        --no-upx)
            export NO_UPX=1
            shift
            ;;
        -*)
            echo -e "${TOMATO}Error: Unknown option $1${NC}"
            usage
            ;;
        *)
            TARGET_ARCH="$(normalize_arch "$1")"
            shift
            ;;
    esac
done

# Check dependencies first
if ! check_dependencies; then
    exit 1
fi

# Initialize cache
init_cache

# Create default nanorc if bundle mode is enabled
if [[ ${BUNDLE_CONFIG} == 1 ]]; then
    create_default_nanorc
fi

# Interactive mode
if [[ ${INTERACTIVE_MODE:-0} == 1 ]]; then
    if interactive_menu; then
        TARGET_ARCH=""  # Clear single arch target
    else
        exit 1
    fi
fi

echo -e "${BWHITE}=== Cross-compilation build script for nano (ENHANCED) ===${NC}"
echo -e "${MINT}Using musl.cc toolchains${NC}"
echo ""

echo -e "${GOLD}Build Configuration:${NC}"
echo -e "  ${CYAN}Nano version:${NC}    ${NANO_VERSION}"
echo -e "  ${CYAN}Ncurses version:${NC} ${NCURSES_VERSION}"
echo -e "  ${CYAN}Workspace:${NC}       ${WORKSPACE}"
echo -e "  ${CYAN}Caching:${NC}         $([ ${ENABLE_CACHE} -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo -e "  ${CYAN}Parallel builds:${NC} $([ ${PARALLEL_MODE} -eq 1 ] && echo "Enabled (${MAX_PARALLEL_BUILDS})" || echo 'Disabled')"
echo -e "  ${CYAN}Config bundling:${NC} $([ ${BUNDLE_CONFIG} -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo ""

mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

# Build logic
if [[ ${#SELECTED_ARCHS[@]} -gt 0 ]]; then
    # Interactive mode selections
    if [[ ${PARALLEL_MODE} == 1 ]]; then
        for arch_name in "${SELECTED_ARCHS[@]}"; do
            for arch in "${ARCHITECTURES[@]}"; do
                IFS=':' read -r display_name toolchain_prefix musl_name <<< "$arch"
                if [ "$display_name" == "$arch_name" ]; then
                    queue_build "$display_name" "$toolchain_prefix" "$musl_name"
                    break
                fi
            done
        done
        process_build_queue
    else
        for arch_name in "${SELECTED_ARCHS[@]}"; do
            for arch in "${ARCHITECTURES[@]}"; do
                IFS=':' read -r display_name toolchain_prefix musl_name <<< "$arch"
                if [ "$display_name" == "$arch_name" ]; then
                    build_for_arch "$display_name" "$toolchain_prefix" "$musl_name"
                    break
                fi
            done
        done
    fi
elif [ -z "$TARGET_ARCH" ]; then
    # Build all architectures
    echo -e "${VIOLET}No architecture specified. Building for all architectures...${NC}"
    
    if [[ ${PARALLEL_MODE} == 1 ]]; then
        for arch in "${ARCHITECTURES[@]}"; do
            IFS=':' read -r display_name toolchain_prefix musl_name <<< "$arch"
            queue_build "$display_name" "$toolchain_prefix" "$musl_name"
        done
        process_build_queue
    else
        FAILED=()
        SUCCEEDED=()
        
        for arch in "${ARCHITECTURES[@]}"; do
            IFS=':' read -r display_name toolchain_prefix musl_name <<< "$arch"
            if build_for_arch "$display_name" "$toolchain_prefix" "$musl_name"; then
                SUCCEEDED+=("$display_name")
            else
                echo -e "${TOMATO}Failed to build for $display_name${NC}"
                FAILED+=("$display_name")
            fi
        done
        
        echo ""
        echo -e "${GREEN}Successful builds (${#SUCCEEDED[@]}): ${SUCCEEDED[*]}${NC}"
        if [ ${#FAILED[@]} -gt 0 ]; then
            echo -e "${TOMATO}Failed builds (${#FAILED[@]}): ${FAILED[*]}${NC}"
        fi
    fi
else
    # Build for specific architecture
    FOUND=false
    
    for arch in "${ARCHITECTURES[@]}"; do
        IFS=':' read -r display_name toolchain_prefix musl_name <<< "$arch"
        if [ "$display_name" == "$TARGET_ARCH" ]; then
            build_for_arch "$display_name" "$toolchain_prefix" "$musl_name"
            FOUND=true
            break
        fi
    done
    
    if [ "$FOUND" == "false" ]; then
        echo -e "${TOMATO}Error: Unknown architecture '$TARGET_ARCH'${NC}"
        echo ""
        usage
    fi
fi

# Summary
echo ""
echo -e "${CORAL}==========================================${NC}"
echo -e "${BWHITE}Build Summary${NC}"
echo -e "${CORAL}==========================================${NC}"
echo -e "${GOLD}Output directory: ${OUTPUT_DIR}${NC}"
echo ""
echo -e "${PINK}Built binaries:${NC}"
ls -lh "${OUTPUT_DIR}" 2>/dev/null || echo -e "${CRIMSON}No binaries found${NC}"
echo ""

if [[ ${PARALLEL_MODE} == 1 ]]; then
    echo -e "${CYAN}Build logs available in: ${WORKSPACE}/logs/${NC}"
    echo ""
fi

echo -e "${PEACH}Installation instructions:${NC}"
echo -e "  ${CREAM}1.${NC} ${SELAGO}Copy the appropriate nano binary to your device${NC}"
echo -e "  ${CREAM}2.${NC} ${BWHITE}chmod +x nano-*${NC}"
echo -e "  ${CREAM}3.${NC} ${BWHITE}mv nano-* /usr/local/bin/nano${NC}"
if [[ ${BUNDLE_CONFIG} == 1 ]]; then
    echo -e "  ${CREAM}4.${NC} ${BWHITE}tar -xzf nano-*-config.tar.gz -C ~/.config/nano/${NC}"
    echo -e "  ${CREAM}5.${NC} ${BWHITE}export TERM=linux${NC}"
else
    echo -e "  ${CREAM}4.${NC} ${BWHITE}export TERM=linux${NC}"
fi
echo ""