#!/bin/bash
# Build nano for various architectures using musl.cc cross-compilers
# Supports multiple architectures without requiring system-installed toolchains
set -e  # Exit on any error

# Configuration
WORKSPACE="${PWD}/build"
PATCHES="${PWD}/patches"
MAIN="${PWD}"
NCURSES_VERSION="${NCURSES_VERSION:-6.6}"
NANO_VERSION="${NANO_VERSION:-8.7}"
MUSL_CC_BASE="https://github.com/gfunkmonk/musl-cross/releases/download/02032026/"

# Color definitions
source ./colors.sh

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
    echo -e "  ${PINK}--inst-dep, inst-dep${NC}     ${SLATE}Tries to install build dependancies${NC}"
    echo ""
    echo -e "${LIGHTROYAL}Available architectures:${NC}"
    for arch in "${ARCHITECTURES[@]}"; do
        IFS=':' read -r display_name toolchain musl_name <<< "$arch"
        echo -e "  ${BLUE}•${NC} ${ORANGE}$display_name${NC}"
    done
    echo ""
    echo -e "${CREAM}Examples:${NC}"
    echo -e "${BWHITE}  $0 mipsel${NC}                                     ${TEAL}# Build for mipsel with default versions${NC}"
    echo -e "${BWHITE}  $0 aarch64 --nano-ver 8.7${NC}                     ${TEAL}# Build for aarch64 with nano 8.7${NC}"
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

return 0
}

# Function to clean
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
    apt-get install -y wget build-essential texinfo file > /dev/null 2>&1
elif command -v yum &> /dev/null; then
    yum install -y wget gcc make texinfo file > /dev/null 2>&1
else
    echo -e "${LEMON}Warning: Could not detect package manager.${NC}"
fi
exit 1
}

# Function to download and extract toolchain
setup_toolchain() {
    local musl_name=$1
    local toolchain_dir="${WORKSPACE}/toolchains/${musl_name}"

    if [ -d "${toolchain_dir}" ]; then
        echo -e "${LEMON}Toolchain ${musl_name} already exists, skipping download...${NC}"
        return 0
    fi

    echo -e "${TAWNY}Downloading ${musl_name} toolchain from musl.cc...${NC}"
    mkdir -p "${WORKSPACE}/toolchains"
    cd "${WORKSPACE}/toolchains"

    local archive="${musl_name}.tar.xz"
    if [ ! -f "${archive}" ]; then
        wget -q --show-progress --tries=3 --timeout=30 "${MUSL_CC_BASE}/${archive}" || {
            echo -e "${TOMATO}Error: Failed to download toolchain ${musl_name}${NC}"
            return 1
        }
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
    local BUILD_CFLAGS="-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer ${arch_cflags}"
    local BUILD_LDFLAGS="-Wl,--gc-sections"

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

    if [ ! -f "ncurses-${NCURSES_VERSION}.tar.gz" ]; then
        wget -q --show-progress --tries=3 --timeout=30 "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" || {
            echo -e "${TOMATO}Error: Failed to download ncurses ${NCURSES_VERSION}${NC}"
            return 1
        }
    fi

    rm -rf "ncurses-${NCURSES_VERSION}"
    tar -xzf "ncurses-${NCURSES_VERSION}.tar.gz"
    cd "ncurses-${NCURSES_VERSION}"

    # Apply patches if they exist
    if [ -d "${PATCHES}/ncurses" ]; then
        for patch in "${PATCHES}"/ncurses/${NCURSES_VERSION}*.patch; do
            if [[ -f "$patch" ]]; then
                echo -e "${JUNEBUD}Applying ${patch##*/}${NC}"
                patch -sp1 --fuzz=8 <"${patch}" || {
                    echo -e "${LEMON}WARNING: Failed to apply patch ${patch##*/}${NC}" >&2
                }
            fi
        done
    fi

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

    make -j"$(nproc)" -s
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
    if [ ! -f "nano-${NANO_VERSION}.tar.xz" ]; then
        wget -q --show-progress --tries=3 --timeout=30 "${NANO_URL}" || {
            echo -e "${TOMATO}Error: Failed to download nano ${NANO_VERSION}${NC}"
            echo -e "${LEMON}Tried URL: ${NANO_URL}${NC}"
            return 1
        }
    fi

    rm -rf "nano-${NANO_VERSION}"
    tar -xf "nano-${NANO_VERSION}.tar.xz"
    cd "nano-${NANO_VERSION}"

    # Apply patches if they exist
    if [ -d "${PATCHES}/nano" ]; then
        for patch in "${PATCHES}"/nano/*.patch; do
            if [[ -f "$patch" ]]; then
                echo -e "${JUNEBUD}Applying ${patch##*/}${NC}"
                patch -sp1 <"${patch}" || {
                    echo -e "${LEMON}WARNING: Failed to apply patch ${patch##*/}${NC}" >&2
                }
            fi
        done
    fi

    echo -e "\n"
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

    make -j"$(nproc)" -s

    # Strip and copy final binary
    export OUTPUT_DIR="${MAIN}/output"
    mkdir -p "${OUTPUT_DIR}"

    echo -e "${AQUA}Stripping binary...${NC}"
    "${toolchain_prefix}"-strip src/nano -o "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}"

    # Compress with UPX if available
    if command -v upx >/dev/null 2>&1; then
        echo -e "${PEACH}Compressing with UPX...${NC}"
        upx --ultra-brute "${OUTPUT_DIR}/nano-${NANO_VERSION}-${display_name}" > /dev/null 2>&1 || {
            echo -e "${LEMON}UPX compression failed, continuing...${NC}"
        }
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

# Parse command line arguments FIRST (before any output)
TARGET_ARCH=""
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
            ;;
        --clean-all|clean-all)
            cleanall
            ;;
        --inst-dep|inst-dep)
            installdep
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

# Main script starts here (after argument parsing)
echo -e "${BWHITE}=== Cross-compilation build script for nano ===${NC}"
echo -e "${MINT}Using musl.cc toolchains${NC}"
echo ""

# Display build configuration
echo -e "${GOLD}Build Configuration:${NC}"
echo -e "  ${CYAN}Nano version:${NC}    ${NANO_VERSION}"
echo -e "  ${CYAN}Ncurses version:${NC} ${NCURSES_VERSION}"
echo -e "  ${CYAN}Workspace:${NC}       ${WORKSPACE}"
echo ""

# Create workspace
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

# Build based on target architecture
if [ -z "$TARGET_ARCH" ]; then
    # Build for all architectures
    echo -e "${VIOLET}No architecture specified. Building for all architectures...${NC}"
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
echo -e "${PEACH}Installation instructions:${NC}"
echo -e " ${CREAM}1.${NC} ${SELAGO}Copy the appropriate nano-[arch] binary to your device${NC}"
echo -e "  ${CREAM}2.${NC} ${BWHITE}chmod +x nano-${RED}[arch]${NC}"
echo -e "  ${CREAM}3.${NC} ${BWHITE}mv nano-${RED}[arch] ${BWHITE}/usr/local/bin/nano${NC}"
echo -e "  ${CREAM}4.${NC} ${BWHITE}export TERM=linux${NC}"
echo ""
echo -e "${LEMON}If you get 'Error opening terminal':${NC}"
echo -e "  ${BWHITE}export TERM=linux${NC}"
echo -e "  ${PURPLE}Or add to ~/.bashrc:${NC} ${GREEN}echo 'export TERM=linux' >> ~/.bashrc${NC}"
echo -e "${NC}"