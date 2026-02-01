#!/bin/bash
# Build nano for various architectures using musl.cc cross-compilers
# Supports multiple architectures without requiring system-installed toolchains
set -e  # Exit on any error

# Configuration
WORKSPACE="${PWD}/build"
PATCHES="${PWD}/patches"
NCURSES_VERSION="${NCURSES_VERSION:-6.4}"
NANO_VERSION="${NANO_VERSION:-8.7}"
MUSL_CC_BASE="https://musl.cc"

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
        m68k) echo "-march=68020 -fomit-frame-pointer -ffreestanding" ;;
        mips64) echo "-mips64 -mabi=64" ;;
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
    "mipsel:mipsel-linux-muslsf:mipsel-linux-muslsf-cross"
    "mips:mips-linux-muslsf:mips-linux-muslsf-cross"
    "arm:arm-linux-musleabi:arm-linux-musleabi-cross"
    "armhf:arm-linux-musleabihf:arm-linux-musleabihf-cross"
    "armv5:armv5l-linux-musleabi:armv5l-linux-musleabi-cross"
    "armv6:armv6-linux-musleabihf:armv6-linux-musleabihf-cross"
    "armv7:armv7l-linux-musleabihf:armv7l-linux-musleabihf-cross"
    "aarch64:aarch64-linux-musl:aarch64-linux-musl-cross"
    "x86_64:x86_64-linux-musl:x86_64-linux-musl-cross"
    "i686:i686-linux-musl:i686-linux-musl-cross"
    "powerpc:powerpc-linux-muslsf:powerpc-linux-muslsf-cross"
    "powerpc64:powerpc64-linux-musl:powerpc64-linux-musl-cross"
    "powerpcle:powerpcle-linux-muslsf:powerpcle-linux-muslsf-cross"
    "powerpc64le:powerpc64le-linux-musl:powerpc64le-linux-musl-cross"
    "riscv32:riscv32-linux-musl:riscv32-linux-musl-cross"
    "riscv64:riscv64-linux-musl:riscv64-linux-musl-cross"
    "s390x:s390x-linux-musl:s390x-linux-musl-cross"
)

# Function to display usage
usage() {
    echo -e "${CYAN}Usage: $0 [options] [architecture]${NC}"
    echo ""
    echo -e "${VIOLET}Options:${NC}"
    echo -e "  ${PINK}--nano-version VERSION${NC}     Set nano version (default: ${NANO_VERSION})"
    echo -e "  ${PINK}--ncurses-version VERSION${NC}  Set ncurses version (default: ${NCURSES_VERSION})"
    echo -e "  ${PINK}-h, --help${NC}                 Show this help message"
    echo ""
    echo -e "${SLATE}Available architectures:${NC}"
    for arch in "${ARCHITECTURES[@]}"; do
        IFS=':' read -r display_name toolchain musl_name <<< "$arch"
        echo -e "  ${GREEN}•${NC} $display_name"
    done
    echo ""
    echo -e "${PURPLE}Examples:${NC}"
    echo -e "  $0 mipsel                                     # Build for mipsel with default versions"
    echo -e "  $0 --nano-version 8.7 aarch64                 # Build for aarch64 with nano 8.7"
    echo -e "  $0 --ncurses-version 6.5 --nano-version 7.2   # Build all archs with custom versions"
    echo -e "  NANO_VERSION=8.1 NCURSES_VERSION=6.3 $0 armv7 # Use environment variables"
    echo ""
    echo -e "${CREAM}Environment Variables:${NC}"
    echo -e "  ${TEAL}NANO_VERSION${NC}      Override default nano version"
    echo -e "  ${TEAL}NCURSES_VERSION${NC}   Override default ncurses version"
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

    local archive="${musl_name}.tgz"
    if [ ! -f "${archive}" ]; then
        wget -q --show-progress "${MUSL_CC_BASE}/${archive}" || {
            echo -e "${TOMATO}Error: Failed to download toolchain ${musl_name}${NC}"
            return 1
        }
    fi

    echo -e "${LAGOON}Extracting toolchain...${NC}"
    tar -xzf "${archive}"

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
    local BUILD_CFLAGS="-Os -static -ffunction-sections -fdata-sections ${arch_cflags}"
    local BUILD_LDFLAGS="-Wl,--gc-sections"

    # Setup toolchain
    setup_toolchain "${musl_name}" || return 1

    local TOOLCHAIN_DIR="${WORKSPACE}/toolchains/${musl_name}"
    local SYSROOT="${WORKSPACE}/sysroot-${display_name}"
    local BUILD_DIR="${WORKSPACE}/build-${display_name}"

    # Add toolchain to PATH
    export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"

    # Verify toolchain
    if ! command -v ${toolchain_prefix}-gcc &> /dev/null; then
        echo -e "${TOMATO}Error: ${toolchain_prefix}-gcc not found in PATH${NC}"
        return 1
    fi

    mkdir -p "${BUILD_DIR}"
    mkdir -p "${SYSROOT}"

    # Build ncurses
    echo -e "${LIGHTROYAL}Building ncurses ${NCURSES_VERSION} for ${display_name}...${NC}"
    cd "${BUILD_DIR}"

    if [ ! -f "ncurses-${NCURSES_VERSION}.tar.gz" ]; then
        wget -q --show-progress "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" || {
            echo -e "${TOMATO}Error: Failed to download ncurses ${NCURSES_VERSION}${NC}"
            return 1
        }
    fi

    rm -rf "ncurses-${NCURSES_VERSION}"
    tar -xzf "ncurses-${NCURSES_VERSION}.tar.gz"
    cd "ncurses-${NCURSES_VERSION}"

    CFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="${BUILD_LDFLAGS}" \
    ./configure \
        --host=${toolchain_prefix} \
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
        --with-fallbacks=linux,screen,vt100,xterm \
        CC=${toolchain_prefix}-gcc \
        STRIP=${toolchain_prefix}-strip
        #> /dev/null 2>&1

    #make -j$(nproc) > /dev/null 2>&1
    #make install > /dev/null 2>&1
    make -j$(nproc) -s
    make install -s

    # Fix ncurses header structure
    echo -e "${TEAL}Fixing ncurses header paths...${NC}"
    cd "${SYSROOT}/include"
    if [ -d "ncurses" ]; then
        cd ncurses
        mkdir -p ncurses
        for f in *.h; do
            [ -f "$f" ] && ln -sf ../$f ncurses/$f
        done
    fi

    # Build nano
    echo -e "${PEACH}Building nano ${NANO_VERSION} for ${display_name}...${NC}"
    cd "${BUILD_DIR}"

    local NANO_URL=$(get_nano_url "${NANO_VERSION}")
    if [ ! -f "nano-${NANO_VERSION}.tar.xz" ]; then
        wget -q --show-progress "${NANO_URL}" || {
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
        for patch in ${PATCHES}/nano/*.patch; do
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
    echo -e "\n"

    CFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="${BUILD_LDFLAGS}" \
    PKG_CONFIG_PATH="${SYSROOT}/lib/pkgconfig" \
    ./configure \
        --host=${toolchain_prefix} \
        --prefix=/usr/local \
        --sysconfdir=/etc \
        --disable-nls \
        --disable-utf8 \
        --enable-tiny \
        --enable-nanorc \
        --enable-color \
        --enable-extra \
        --disable-justify \
        --enable-largefile \
        CC=${toolchain_prefix}-gcc \
        CPPFLAGS="-I${SYSROOT}/include/ncurses -I${SYSROOT}/include" \
        LDFLAGS="-L${SYSROOT}/lib ${BUILD_LDFLAGS}"
        #> /dev/null 2>&1

    #make -j$(nproc) > /dev/null 2>&1
    make -j$(nproc) -s

    # Strip and copy final binary
    local OUTPUT_DIR="${WORKSPACE}/output"
    mkdir -p "${OUTPUT_DIR}"

    echo -e "${AQUA}Stripping binary...${NC}"
    ${toolchain_prefix}-strip src/nano -o "${OUTPUT_DIR}/nano-${display_name}"

    # Compress with UPX if available
    if command -v upx >/dev/null 2>&1; then
        echo -e "${PEACH}Compressing with UPX...${NC}"
        upx --ultra-brute "${OUTPUT_DIR}/nano-${display_name}" > /dev/null 2>&1 || {
            echo -e "${LEMON}UPX compression failed, continuing...${NC}"
        }
    fi

    echo -e "${MINT}✓ Build complete for ${display_name}!${NC}"
    echo -e "${HELIOTROPE}Binary: ${OUTPUT_DIR}/nano-${display_name}${NC}"

    # Display binary info
    local file_info=$(file "${OUTPUT_DIR}/nano-${display_name}" | cut -d: -f2-)
    local size_info=$(du -h "${OUTPUT_DIR}/nano-${display_name}" 2>/dev/null | cut -f1)
    
    echo -e "${NAVAJO}Type: ${file_info}${NC}"
    echo -e "${SKY}Size: ${size_info}${NC}"
    echo -e "${CREAM} $(ls -lh "${OUTPUT_DIR}/nano-${display_name}")${NC}"
}

# Parse command line arguments FIRST (before any output)
TARGET_ARCH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --nano-version)
            NANO_VERSION="$2"
            shift 2
            ;;
        --ncurses-version)
            NCURSES_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo -e "${TOMATO}Error: Unknown option $1${NC}"
            usage
            ;;
        *)
            TARGET_ARCH="$1"
            shift
            ;;
    esac
done

# Main script starts here (after argument parsing)
echo -e "${BWHITE}=== Cross-compilation build script for nano ===${NC}"
echo -e "${MINT}Using musl.cc toolchains${NC}"
echo ""

# Install basic build dependencies (commented out - enable if needed)
 echo -e "${ORANGE}Installing build dependencies...${NC}"
 if command -v apt-get &> /dev/null; then
     apt-get update > /dev/null 2>&1
     apt-get install -y wget build-essential texinfo file > /dev/null 2>&1
 elif command -v yum &> /dev/null; then
     yum install -y wget gcc make texinfo file > /dev/null 2>&1
 else
     echo -e "${LEMON}Warning: Could not detect package manager.${NC}"
 fi


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
echo -e "${GOLD}Output directory: ${WORKSPACE}/output${NC}"
echo ""
echo -e "${PINK}Built binaries:${NC}"
ls -lh "${WORKSPACE}/output/" 2>/dev/null || echo -e "${CRIMSON}No binaries found${NC}"
echo ""
echo -e "${SELAGO}Installation instructions:${NC}"
echo -e "  1. Copy the appropriate nano-[arch] binary to your device"
echo -e "  2. ${BWHITE}chmod +x nano-[arch]${NC}"
echo -e "  3. ${BWHITE}mv nano-[arch] /usr/local/bin/nano${NC}"
echo -e "  4. ${BWHITE}export TERM=linux${NC}"
echo ""
echo -e "${LEMON}If you get 'Error opening terminal':${NC}"
echo -e "  ${BWHITE}export TERM=linux${NC}"
echo -e "  ${PURPLE}Or add to ~/.bashrc:${NC} ${GREEN}echo 'export TERM=linux' >> ~/.bashrc${NC}"
echo -e "${NC}"