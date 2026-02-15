#!/bin/bash
# Build nano for various architectures using musl.cc cross-compilers
# Supports multiple architectures without requiring system-installed toolchains
set -e  # Exit on any error
#set -x

# Configuration
WORKSPACE="${PWD}/build"
PATCHES="${PWD}/patches"
MAIN="${PWD}"
NCURSES_VERSION="${NCURSES_VERSION:-6.6}"
NANO_VERSION="${NANO_VERSION:-8.7.1}"
MUSL_CC_BASE="https://github.com/gfunkmonk/musl-cross/releases/download/02032026/"
OUTPUT_DIR="${MAIN}/output"
CACHE_DIR="${WORKSPACE}/cache"
ENABLE_CACHE="${ENABLE_CACHE:-1}"
MAX_PARALLEL_BUILDS="${MAX_PARALLEL_BUILDS:-3}"
PARALLEL_MODE="${PARALLEL_MODE:-0}"

# Color definitions
source ./colors.sh

# Normalize architecture names
normalize_arch() {
    local raw_arch=$1
    case "$raw_arch" in
        arm64|armv8) echo "aarch64" ;;
        arm|armel|armv6l) echo "armv6" ;;
        armv7l|armhf) echo "armv7" ;;
        i386|x32|x86) echo "i686" ;;
        68000) echo "m68k" ;;
        mblaze) echo "microblaze" ;;
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
        armv6) echo "-march=armv6kz -mfloat-abi=hard -mfpu=vfp" ;;
        armv7) echo "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
        i486) echo "-march=i486 -mtune=generic" ;;
        i586) echo "-march=i586 -mtune=generic" ;;
        i686) echo "-march=pentium-m -mfpmath=sse -mtune=generic" ;;
        loongarch64) echo "-march=loongarch64 -mabi=lp64d -mtune=la464" ;;
        m68k) echo "-march=68020 -fomit-frame-pointer -ffreestanding" ;;
        mips) echo "-march=mips32 -mabi=32" ;;
        mipsel) echo "-march=mips32 -mplt -mabi=32" ;;
        mips64) echo "-march=mips64 -mabi=64" ;;
        mips64el) echo "-mplt -mabi=64" ;;
        powerpc) echo "-mpowerpc -m32" ;;
        powerpcle) echo "-m32" ;;
        powerpc64) echo "-mpowerpc64 -m64 -falign-functions=32 -falign-labels=32 -falign-loops=32 -falign-jumps=32" ;;
        powerpc64le) echo "-m64 -falign-functions=32 -falign-labels=32 -falign-loops=32 -falign-jumps=32" ;;
        riscv64) echo "-march=rv64gc -mabi=lp64d" ;;
        riscv32) echo "-ffreestanding -Wno-implicit-function-declaration -Wno-int-conversion" ;;
        s390x) echo "-march=z196 -mtune=z15" ;;
        sh4) echo "-fstack-protector-strong" ;;
        x86_64) echo "-march=x86-64 -mtune=generic" ;;
        *) echo "" ;;
    esac
}

# Determine nano download URL based on version
get_nano_url() {
    local version=$1
    local major_version="${version%%.*}"

    # Nano versions 7.x and 8.x are in different directories
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
# Format: "display_name:toolchain_prefix:musl_cc_name"
ARCHITECTURES=(
    #"arm:arm-unknown-linux-musleabi:arm-unknown-linux-musleabi"
    #"armhf:arm-unknown-linux-musleabihf:arm-unknown-linux-musleabihf"
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
    echo -e "  ${PINK}--check-deps${NC}             ${SLATE}Check for missing dependencies${NC}"
    echo -e "  ${PINK}--inst-dep, inst-dep${NC}     ${SLATE}Tries to install build dependancies${NC}"
    echo -e "  ${PINK}--njobs NUMBER${NC}           ${SLATE}Number of parallel jobs (default: auto)${NC}"
    echo -e "  ${PINK}--extra-cflags 'VALUE'${NC}   ${SLATE}Extra CFLAGS to append to default${NC}"
    echo -e "  ${PINK}--no-upx${NC}                 ${SLATE}Skip UPX compression${NC}"
    echo -e "  ${PINK}--parallel [NUM]${NC}         ${SLATE}Build multiple architectures in parallel (default: 3)${NC}"
    echo -e "  ${PINK}--no-cache${NC}               ${SLATE}Disable caching of downloads${NC}"
    echo -e "  ${PINK}--clear-cache${NC}            ${SLATE}Clear the download cache${NC}"
    echo -e "  ${PINK}--interactive, -i${NC}        ${SLATE}Interactive menu mode (requires dialog)${NC}"
    echo ""
    echo -e "${LIGHTROYAL}Available architectures:${NC}"
    for arch in "${ARCHITECTURES[@]}"; do
        IFS=':' read -r display_name toolchain musl_name <<< "$arch"
        echo -e "  ${BLUE}•${NC} ${ORANGE}$display_name${NC}"
    done
    echo ""
    echo -e "${CREAM}Examples:${NC}"
    echo -e "${BWHITE}  $0 mipsel${NC}                                     ${TEAL}# Build for mipsel with default versions${NC}"
    echo -e "${BWHITE}  $0 --nano-ver 8.7 aarch64${NC}                     ${TEAL}# Build for aarch64 with nano 8.7${NC}"
    echo -e "${BWHITE}  $0 --ncurses-ver 6.1 --nano-ver 7.2${NC}           ${TEAL}# Build all archs with custom versions${NC}"
    echo -e "${BWHITE}  NANO_VERSION=8.2 NCURSES_VERSION=6.0 $0 armv7${NC} ${TEAL}# Use environment variables${NC}"
    echo ""
    echo -e "${NAVAJO}Environment Variables:${NC}"
    echo -e "  ${BWHITE}NANO_VERSION${NC}      ${DKPURPLE}Override default nano version"
    echo -e "  ${BWHITE}NCURSES_VERSION${NC}   ${DKPURPLE}Override default ncurses version"
    exit 1
}

# Function to clean
cleanup() {
    read -p "Are you sure you want to continue? (y/n): " -n 1 confirmation
echo "" # Add a newline after the single character input

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
echo "" # Add a newline after the single character input

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

    # Expand glob pattern properly
    shopt -s nullglob
    local patches=()
    while IFS= read -r -d '' patch; do
        patches+=("$patch")
    done < <(find "$patch_dir" -maxdepth 1 -name "$patch_pattern" -type f -print0 | sort -z)

    if [[ ${#patches[@]} -eq 0 ]]; then
        return 0
    fi

    # Apply patches......
    local display_dir="${patch_dir#$PATCHES/}"
    echo -e "${HELIOTROPE}= Applying patches from ${display_dir}${NC}"

    for patch in "${patches[@]}"; do
        echo -e "${PEACH}Applying ${patch##*/}${NC}"
        # Get absolute path to patch
        local abs_patch=$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")
        pushd "$target_dir" >/dev/null
        patch -sp1 --fuzz=4 < "${abs_patch}" || {
            echo -e "${LEMON}WARNING: Failed to apply patch ${patch##*/}${NC}" >&2
        }
        popd >/dev/null
    done
}

# Get number of parallel jobs with better detection
get_parallel_jobs() {
    if [[ -n ${NJOBS:-} ]]; then
        echo "$NJOBS"
    elif command -v nproc >/dev/null 2>&1; then
        # Use all cores for extraction/patching, N-1 for compilation to avoid overload
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.physicalcpu
    else
        echo "1"
    fi
}

# Functoion to check for required dependencies
check_dependencies() {
    local missing_deps=()
    local optional_deps=()

    echo -e "${PURPLE}Checking build dependencies...${NC}"

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
        echo -e "  ${ORANGE}○${NC} upx (optional - for compression)"
    else
        echo -e "  ${SKY}✓${NC} upx (optional)"
    fi

    if ! command -v dialog &> /dev/null && [[ ${INTERACTIVE_MODE:-0} == 1 ]]; then
        optional_deps+=("dialog (for interactive mode)")
        echo -e "  ${CANARY}○${NC} dialog (optional - for interactive menu)"
    fi

    # Report missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        echo -e "${TOMATO}Missing required dependencies:${NC}"
        for dep in "${missing_deps[@]}"; do
            echo -e "  ${TOMATO}✗${NC} $dep"
        done
        echo ""
        echo -e "${CANARY}Install them with:${NC}"

        if command -v apt-get &> /dev/null; then
            echo -e "  ${BWHITE}sudo apt-get install -y wget tar make gcc patch file build-essential${NC}"
        elif command -v yum &> /dev/null; then
            echo -e "  ${BWHITE}sudo yum install -y wget tar make gcc patch file${NC}"
        elif command -v pacman &> /dev/null; then
            echo -e "  ${BWHITE}sudo pacman -S wget tar make gcc patch file${NC}"
        else
            echo -e "  ${VIOLET}Please install using your system's package manager${NC}"
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

# Function for caching
# Initialize cache directory
init_cache() {
    if [[ ${ENABLE_CACHE} == 1 ]]; then
        mkdir -p "${CACHE_DIR}/downloads"
        mkdir -p "${CACHE_DIR}/extracted"
        echo -e "${LIME}Cache enabled at: ${CACHE_DIR}${NC}"
    fi
}

# Check if file exists in cache
check_cache() {
    local file=$1
    local cache_path="${CACHE_DIR}/downloads/${file}"

    if [[ ${ENABLE_CACHE} == 1 ]] && [[ -f "${cache_path}" ]]; then
        echo -e "${CHARTREUSE}Found in cache: ${file}${NC}"
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
        echo -e "${PURPLE}Cached: ${filename}${NC}"
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
        echo -e "${MINT}Clearing cache...${NC}"
        rm -rf "${CACHE_DIR}"
        echo -e "${GREEN}Cache cleared${NC}"
    fi
}

# Function for parallel archetecture builds
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

    echo -e "${PEACH}Started build for ${display_name} (PID: ${pid})${NC}"
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
                    echo -e "${LIME}✓ Completed: ${arch}${NC}"
                else
                    echo -e "${TOMATO}✗ Failed: ${arch}${NC}"
                    echo -e "${LEMON}  See log: ${WORKSPACE}/logs/build-${arch}.log${NC}"
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
    echo -e "${BLUE}Waiting for remaining builds to complete...${NC}"
    for arch in "${RUNNING_BUILDS[@]}"; do
        local pid="${BUILD_PIDS[$arch]}"
        wait "$pid" || true

        local status_file="${WORKSPACE}/logs/build-${arch}.status"
        if [[ -f "${status_file}" ]] && [[ $(cat "${status_file}") == "0" ]]; then
            echo -e "${KHAKI}✓ Completed: ${arch}${NC}"
        else
            echo -e "${CRIMSON}✗ Failed: ${arch}${NC}"
        fi
    done
}

# Function for interactive menu
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
        echo -e "${TOMATO}No architectures selected${NC}"
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
        2 "Skip UPX compression" off \
        3 "Enable caching" on \
        4 "Number of jobs" off \
        5 "Extra CFLAGS" off)

    if echo "$build_opts" | grep -q "1"; then
        PARALLEL_MODE=1
        MAX_PARALLEL_BUILDS=$(dialog --stdout --inputbox \
            "Max parallel builds:" 8 40 "3")
    fi

    if echo "$build_opts" | grep -q "2"; then
        NO_UPX=1
    fi

    if ! echo "$build_opts" | grep -q "3"; then
        ENABLE_CACHE=0
    fi

    if echo "$build_opts" | grep -q "4"; then
        local njobs=$(dialog --stdout --inputbox \
            "Number of jobs:" 8 40 "${NJOBS}")
        [[ -n "$njobs" ]] && NJOBS="$njobs"
    fi

    if echo "$build_opts" | grep -q "5"; then
        local extra_cflags=$(dialog --stdout --inputbox \
            "Extra CFLAGS:" 8 40 "${EXTRA_CFLAGS}")
        [[ -n "$extra_cflags" ]] && EXTRA_CFLAGS="$extra_cflags"
    fi

    # Convert selections to architecture names
    SELECTED_ARCHS=()
    for num in $selected; do
        local idx=$((num - 1))
        IFS=':' read -r display_name _ _ <<< "${ARCHITECTURES[$idx]}"
        SELECTED_ARCHS+=("$display_name")
    done

    clear
    echo -e "${TURQUOISE}Selected architectures: ${SELECTED_ARCHS[*]}${NC}"
    echo -e "${ORANGE}Nano version: ${NANO_VERSION}${NC}"
    echo -e "${ORANGE}Ncurses version: ${NCURSES_VERSION}${NC}"
    echo ""

    return 0
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

    # Get architecture-specific CFLAGS
    local norm_arch=$(normalize_arch "$display_name")
    local arch_cflags=$(get_arch_cflags "$norm_arch")

    # Set build-specific flags
    if [[ -n ${EXTRA_CFLAGS:-} ]]; then
       local BUILD_CFLAGS="-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer ${arch_cflags} ${EXTRA_CFLAGS}"
    else
       local BUILD_CFLAGS="-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer ${arch_cflags}"
    fi
    local BUILD_LDFLAGS="-Wl,--gc-sections"
    # Add custom CFLAGS if provided

    # Setup toolchain
    setup_toolchain "${musl_name}" || return 1

    local TOOLCHAIN_DIR="${WORKSPACE}/toolchains/${musl_name}"
    local SYSROOT="${WORKSPACE}/sysroot-${display_name}"
    local BUILD_DIR="${WORKSPACE}/build-${display_name}"

    # Add toolchain to PATH
    export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"

    # Verify toolchain
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

    # Apply custom ncurses patches
    echo -e "\n"
    apply_patches_parallel "$PATCHES/ncurses" "$BUILD_DIR/ncurses-${NCURSES_VERSION}" "${NCURSES_VERSION}*.patch"
    echo -e "\n"
    sleep 3

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

    # Fix ncurses header structure
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

    # Apply custom nano patches
    echo -e "\n"
    apply_patches_parallel "$PATCHES/nano" "$BUILD_DIR/nano-${NANO_VERSION}" "nano-*.patch"
    echo -e "\n"

    if [[ $(echo "${NANO_VERSION} < 8.0" | bc) == 1 ]]; then
       echo -e "\n"
       apply_patches_parallel "$PATCHES/nano" "$BUILD_DIR/nano-${NANO_VERSION}" "nano7-*.patch"
       echo -e "\n"
    fi

    sleep 3

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

    # Strip and copy final binary
    export OUTPUT_DIR="${MAIN}/output"
    mkdir -p "${OUTPUT_DIR}"

    echo -e "${AQUA}Stripping binary...${NC}"
    "${toolchain_prefix}"-strip src/nano -o "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}"

    # Compress with UPX if available
    if [[ ! ${NO_UPX:-} ]] && command -v upx >/dev/null 2>&1; then
        echo -e "${PEACH}Compressing with UPX...${NC}"
        upx --ultra-brute "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" > /dev/null 2>&1 || {
            echo -e "${LEMON}UPX compression failed, continuing...${NC}"
        }
    elif [[ ${NO_UPX:-} ]]; then
        echo -e "${JUNEBUD}UPX compression disabled...${NC}"
    fi


    echo -e "${MINT}✓ Build complete for ${display_name}!${NC}"
    echo -e "${HELIOTROPE}Binary: ${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}${NC}"

    # Display binary info
    local file_info=$(file "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" | cut -d: -f2-)
    local size_info=$(du -h "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" 2>/dev/null | cut -f1)

    echo -e "${NAVAJO}Type: ${file_info}${NC}"
    echo -e "${SKY}Size: ${size_info}${NC}"
    echo -e "${CREAM} $(ls -lh "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}")${NC}"
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

# Interactive mode
if [[ ${INTERACTIVE_MODE:-0} == 1 ]]; then
    if interactive_menu; then
        TARGET_ARCH=""  # Clear single arch target
    else
        exit 1
    fi
fi

echo -e "${BWHITE}=== Cross-compilation build script for nano ===${NC}"
echo -e "${MINT}Using musl.cc toolchains${NC}"
echo ""

echo -e "${GOLD}Build Configuration:${NC}"
echo -e "  ${CYAN}Nano version:${NC}    ${BWHITE}${NANO_VERSION}${NC}"
echo -e "  ${CYAN}Ncurses version:${NC} ${BWHITE}${NCURSES_VERSION}${NC}"
echo -e "  ${CYAN}Workspace:${NC}       ${BWHITE}${WORKSPACE}${NC}"
echo -e "  ${CYAN}Caching:${NC}         ${BWHITE}$([ ${ENABLE_CACHE} -eq 1 ] && echo 'Enabled' || echo 'Disabled')${NC}"
echo -e "  ${CYAN}Parallel builds:${NC} ${BWHITE}$([ ${PARALLEL_MODE} -eq 1 ] && echo "Enabled (${MAX_PARALLEL_BUILDS})" || echo 'Disabled')${NC}"
echo -e "  ${CYAN}Number of jobs:${NC}  ${BWHITE}$([[ -n ${NJOBS:-} ]] && echo "Enabled (${NJOBS})" || echo 'Disabled')${NC}"
echo -e "  ${CYAN}Extra CFLAGS:${NC}    ${BWHITE}${EXTRA_CFLAGS}${NC}"
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
ls -lh --color=auto "${OUTPUT_DIR}" 2>/dev/null || echo -e "${CRIMSON}No binaries found${NC}"
echo ""

if [[ ${PARALLEL_MODE} == 1 ]]; then
    echo -e "${CYAN}Build logs available in: ${WORKSPACE}/logs/${NC}"
    echo ""
fi

echo -e "${PEACH}Installation instructions:${NC}"
echo -e "  ${CREAM}1.${NC} ${SELAGO}Copy the appropriate nano binary to your device${NC}"
echo -e "  ${CREAM}2.${NC} ${BWHITE}chmod +x nano-*${NC}"
echo -e "  ${CREAM}3.${NC} ${BWHITE}mv nano-* /usr/local/bin/nano${NC}"
echo -e "  ${CREAM}4.${NC} ${BWHITE}export TERM=linux${NC}"
echo ""
echo -e "${LEMON}If you get 'Error opening terminal':${NC}"
echo -e "  ${BWHITE}export TERM=linux${NC}"
echo -e "  ${PURPLE}Or add to ~/.bashrc:${NC} ${GREEN}echo 'export TERM=linux' >> ~/.bashrc${NC}"
