#!/usr/bin/env bash
#
#  SPDX-License-Identifier: GPL-3.0-or-later
#

# osxbuild.sh automates building and installing of krita and krita dependencies
# for OSX, the script only needs you to set BUILDROOT environment to work
# properly.
#

# Run with no args for a short help about each command.

# builddeps: Attempts to build krita dependencies in the necessary order,
#     intermediate steps for creating symlinks and fixing rpath of some
#     packages midway is also managed. Order goes from top to bottom, to add
#     new steps just place them in the proper place.

# build: Runs cmake build and make step for krita sources. It always run cmake step, so
#     it might take a bit longer than a pure <make> on the source tree. The script tries
#     to set the make flag -jN to a proper N.

# install: Runs install step for krita sources.

# fixboost: Search for all libraries using boost and sets a proper @rpath for boost as by
#     default it fails to set a proper @rpath

# buildinstall: Runs build, install and fixboost steps.#

if test -z $BUILDROOT; then
    echo "ERROR: BUILDROOT env not set, exiting!"
    echo "\t Must point to the root of the buildfiles as stated in 3rdparty Readme"
    exit 1
fi

BUILDROOT="${BUILDROOT%/}"
echo "BUILDROOT set to ${BUILDROOT}"

# global options
set -o pipefail

# Check cmake in path.
if test -z $(which cmake); then
    echo "WARNING: no cmake in PATH... adding default /Applications location"
    export PATH=/Applications/CMake.app/Contents/bin:${PATH}
    if test -z $(which cmake); then
        echo "ERROR: cmake not found, exiting!"
        exit 1
    fi
fi
echo "$(cmake --version | head -n 1)"

# Set some global variables.
OSXBUILD_TYPE="RelWithDebInfo"
OSXBUILD_TESTING="OFF"
OSXBUILD_HIDE_SAFEASSERTS="ON"

# -- Parse input args
for arg in "${@}"; do
    if [[ "${arg}" = --dirty ]]; then
        OSXBUILD_CLEAN="keep dirty"
    elif [[ "${arg}" = --debug ]]; then
        OSXBUILD_TYPE="Debug"
    elif [[ "${arg}" = --tests ]]; then
        OSXBUILD_TESTING="ON"
    elif [[ "${arg}" = --install_tarball ]]; then
        OSXBUILD_TARBALLINSTALL="TRUE"
    elif [[ "${arg}" = --universal ]]; then
        OSXBUILD_UNIVERSAL="TRUE"
    elif [[ "${arg}" = --showasserts ]]; then
        OSXBUILD_HIDE_SAFEASSERTS="OFF"
    else
        parsed_args="${parsed_args} ${arg}"
    fi
done

export KIS_SRC_DIR=${BUILDROOT}/krita
export KIS_TBUILD_DIR=${BUILDROOT}/depbuild
export KIS_TDEPINSTALL_DIR=${BUILDROOT}/depinstall
export KIS_DOWN_DIR=${BUILDROOT}/down
export KIS_BUILD_DIR=${BUILDROOT}/kisbuild
export KIS_PLUGIN_BUILD_DIR=${BUILDROOT}/plugins_build
export KIS_INSTALL_DIR=${BUILDROOT}/i

# flags for OSX environment
# Qt only supports from 10.12 up, and https://doc.qt.io/qt-5/macos.html#target-platforms warns against setting it lower
export MACOSX_DEPLOYMENT_TARGET=10.13
export QMAKE_MACOSX_DEPLOYMENT_TARGET=10.13


export PATH=${KIS_INSTALL_DIR}/bin:$PATH
export PKG_CONFIG_PATH=${KIS_INSTALL_DIR}/share/pkgconfig:${KIS_INSTALL_DIR}/lib/pkgconfig
export CMAKE_PREFIX_PATH=${KIS_INSTALL_DIR}
export LIBRARY_PATH=${KIS_INSTALL_DIR}/lib:/usr/lib:${LIBRARY_PATH}
export FRAMEWORK_PATH=${KIS_INSTALL_DIR}/lib/

export LIBRARY_PATH=${KIS_INSTALL_DIR}/lib
export C_INCLUDE_PATH=${KIS_INSTALL_DIR}/include
export CPLUS_INCLUDE_PATH=${KIS_INSTALL_DIR}/include


# export PYTHONHOME=${KIS_INSTALL_DIR}
# export PYTHONPATH=${PYTHONPATH}:${KIS_INSTALL_DIR}/lib/Python.framework/Versions/Current/lib/python3.9/site-packages

# This will make the debug output prettier
export KDE_COLOR_DEBUG=1
export QTEST_COLORED=1

export OUPUT_LOG="${BUILDROOT}/osxbuild.log"
printf "" > "${OUPUT_LOG}"

# configure max core for make compile
((MAKE_THREADS=1))
if [[ "${OSTYPE}" == "darwin"* ]]; then
    ((MAKE_THREADS = $(sysctl -n hw.logicalcpu) - 1))
    export MAKEFLAGS="-j${MAKE_THREADS}"
fi

OSXBUILD_X86_64_BUILD=$(sysctl -n hw.optional.x86_64)

if [[ $(arch) = "arm64" ]]; then
    OSX_ARCHITECTURES="arm64"
else
    OSX_ARCHITECTURES="x86_64"
fi

if [[ ${OSXBUILD_UNIVERSAL} ]]; then
    OSX_ARCHITECTURES="x86_64\;arm64"
fi

OSXBUILD_GENERATOR="Unix Makefiles"
if [[ -e $(which ninja) ]]; then
    OSXBUILD_GENERATOR="Ninja"
fi

# Prints stderr and stdout to log files
# >(tee) works but breaks sigint
log_cmd () {
    "$@" 2>&1 | tee -a ${OUPUT_LOG}
    osxbuild_error="${?}"
}

# Log messages to logfile
log () {
    printf "%s\n" "${@}"  | tee -a ${OUPUT_LOG}
}

# if previous command gives error
# print msg
# if a 2nd arg is given it stops execution
print_if_error() {
    if [ "${osxbuild_error}" -ne 0 ]; then
        printf "\e[31m%s %s\e[0m\n" "Error:" "Printing last lines of log output"
        tail ${OUPUT_LOG}
        printf "\e[31m%s %s\e[0m\n" "Error:" "${1}"
        if [ -n "${2}" ]; then
            exit 1
        fi
    fi
}

# print status messages
print_msg() {
    printf "\e[32m%s\e[0m\n" "${1}"
    printf "%s\n" "${1}" >> ${OUPUT_LOG}
}

check_dir_path () {
    printf "%s" "Checking if ${1} exists and is dir... "
    if test -d ${1}; then
        echo -e "OK"

    elif test -e ${1}; then
        echo -e "\n\tERROR: file ${1} exists but is not a directory!" >&2
        return 1
    else
        echo -e "Creating ${1}"
        mkdir ${1}
    fi
    return 0
}

waiting_fixed() {
    local message="${1}"
    local waitTime=${2}

    for i in $(seq ${waitTime}); do
        sleep 1
        printf -v dots '%*s' ${i}
        printf -v spaces '%*s' $((${waitTime} - $i))
        printf "\r%s [%s%s]" "${message}" "${dots// /.}" "${spaces}"
    done
    printf "\n"
}

dir_clean() {
    if [[ -d "${1}" ]]; then
        log "Default cleaning build dirs, use --dirty to keep them..."
        waiting_fixed "Erase of ${1} in 5 sec" 5
        rm -rf "${1}"
    fi
}

# builds dependencies for the first time
cmake_3rdparty () {
    cd ${KIS_TBUILD_DIR}

    local build_pkgs=("${@}") # convert to array
    local error="false"

    if [[ ${2} = "1" ]]; then
        local nofix="true"
        local build_pkgs=(${build_pkgs[@]:0:1})
    fi

    for package in ${build_pkgs[@]} ; do
        if [[ ${package:0:3} != "ext" ]]; then
            continue
        fi
        print_msg "Building ${package}"
        log_cmd cmake --build . --config RelWithDebInfo -j${MAKE_THREADS} --target ${package}

        print_if_error "Failed build ${package}"
        if [[ ! ${osxbuild_error} -ne 0 ]]; then
            print_msg "Build Success! ${package}"
        else
            log "${pkg} build fail, attempting known fixes..."
            error="true"
        fi
        # fixes does not depend on failure
        if [[ ! ${nofix} ]]; then
            build_3rdparty_fixes ${package} ${error}
        elif [[ "${error}" = "true" ]]; then
            log "ERROR: ${pkg} failed a second time, please check pkg logs"
            log "stopping..."
        fi
    done
}

cmake_3rdparty_plugins () {
    cd ${KIS_PLUGIN_BUILD_DIR}

    local build_pkgs=("${@}") # convert to array
    local error="false"

    if [[ ${2} = "1" ]]; then
        local build_pkgs=(${build_pkgs[@]:0:1})
    fi

    for package in ${build_pkgs[@]} ; do
        if [[ ${package:0:3} != "ext" ]]; then
            continue
        fi
        print_msg "Building ${package}"
        log_cmd cmake --build . --config RelWithDebInfo -j${MAKE_THREADS} --target ${package}

        print_if_error "Failed build ${package}"
        if [[ ! ${osxbuild_error} -ne 0 ]]; then
            print_msg "Build Success! ${package}"
        else
            log "${pkg} build fail, stopping..."
            exit 1
        fi
    done
}

build_3rdparty_fixes(){
    local pkg=${1}
    local error=${2}

    if [[ "${pkg}" = "ext_qt" && -e "${KIS_INSTALL_DIR}/bin/qmake" ]]; then
        ln -sf qmake "${KIS_INSTALL_DIR}/bin/qmake-qt5"
        # build macdeployqt
        log_cmd cd "${BUILDROOT}/depbuild/ext_qt/ext_qt-prefix/src/ext_qt/qttools/src"
        print_if_error "macdeployqt source dir was not found, it will be missing for deployment!"

        if [[ ! ${osxbuild_error} -ne 0 && ! -e "${KIS_INSTALL_DIR}/bin/macdeployqt" ]]; then
            make sub-macdeployqt-all
            make sub-macdeployqt-install_subtargets
            make install
        fi
        cd "${KIS_TBUILD_DIR}"
        error="false"

    elif [[ "${pkg}" = "ext_openexr" ]]; then
        # open exr will fail the first time is called
        # rpath needs to be fixed an build rerun
        log "Fixing rpath on openexr file: b44ExpLogTable"
        log "Fixing rpath on openexr file: dwaLookups"
        log_cmd install_name_tool -add_rpath ${KIS_INSTALL_DIR}/lib $(find ${KIS_TBUILD_DIR}/ext_openexr/ext_openexr-prefix/src/ext_openexr-build -name b44ExpLogTable)
        log_cmd install_name_tool -add_rpath ${KIS_INSTALL_DIR}/lib $(find ${KIS_TBUILD_DIR}/ext_openexr/ext_openexr-prefix/src/ext_openexr-build -name dwaLookups)
        # we must rerun build!
        cmake_3rdparty ext_openexr "1"
        error="false"

    elif [[ "${pkg}" = "ext_fontconfig" ]]; then
        log "fixing rpath on fc-cache"
        log_cmd install_name_tool -add_rpath ${KIS_INSTALL_DIR}/lib ${KIS_TBUILD_DIR}/ext_fontconfig/ext_fontconfig-prefix/src/ext_fontconfig-build/fc-cache/.libs/fc-cache
        # rerun rebuild
        if [[ ${OSXBUILD_X86_64_BUILD} -ne 1 && ${osxbuild_error} -ne 0 ]]; then
            print_msg "Build Success! ${pkg}"
        else
            cmake_3rdparty ext_fontconfig "1"
        fi
        error="false"

    elif [[ "${pkg}" = "ext_poppler" && "${error}" = "true" ]]; then
        log "re-running poppler to avoid possible glitch"
        cmake_3rdparty ext_poppler "1"
        error="false"
    fi

    if [[ "${error}" = "true" ]]; then
        log "Error building package ${pkg}, stopping..."
        exit 1
    fi
}

build_3rdparty () {
    print_msg "building in ${KIS_TBUILD_DIR}"

    log "$(check_dir_path ${KIS_TBUILD_DIR})"
    log "$(check_dir_path ${KIS_DOWN_DIR})"
    log "$(check_dir_path ${KIS_INSTALL_DIR})"

    cd ${KIS_TBUILD_DIR}

    log_cmd cmake ${KIS_SRC_DIR}/3rdparty/ \
        -G "${OSXBUILD_GENERATOR}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=10.13 \
        -DCMAKE_INSTALL_PREFIX=${KIS_INSTALL_DIR} \
        -DCMAKE_PREFIX_PATH:PATH=${KIS_INSTALL_DIR} \
        -DEXTERNALS_DOWNLOAD_DIR=${KIS_DOWN_DIR} \
        -DINSTALL_ROOT=${KIS_INSTALL_DIR} \
        -DCMAKE_OSX_ARCHITECTURES=${OSX_ARCHITECTURES} \
        -DMACOS_UNIVERSAL=${OSXBUILD_UNIVERSAL}

        # -DCPPFLAGS=-I${KIS_INSTALL_DIR}/include \
        # -DLDFLAGS=-L${KIS_INSTALL_DIR}/lib

    print_msg "finished 3rdparty build setup"

    if [[ -n ${1} ]]; then
        cmake_3rdparty "${@}"
        # log "Syncing install backup..."
        # rsync -a --delete "${KIS_INSTALL_DIR}" "${KIS_INSTALL_DIR}.onlydeps"
        exit
    fi

    # build 3rdparty tools
    # The order must not be changed!
    cmake_3rdparty \
        ext_zlib \
        ext_iconv \
        ext_pkgconfig \
        ext_gettext \
        ext_openssl \
        ext_python \
        ext_qt \
        ext_boost \
        ext_eigen3 \
        ext_exiv2 \
        ext_fftw3 \
        ext_jpeg \
        ext_lcms2 \
        ext_ocio \
        ext_openexr

    cmake_3rdparty \
        ext_png \
        ext_tiff \
        ext_openjpeg \
        ext_gsl \
        ext_libraw \
        ext_giflib \
        ext_freetype \
        ext_fontconfig \
        ext_poppler

    # Stop if qmake link was not created
    # this meant qt build fail and further builds will
    # also fail.
    log_cmd test -L "${KIS_INSTALL_DIR}/bin/qmake-qt5"

    print_if_error "qmake link missing!"
    if [[ ${osxbuild_error} -ne 0 ]]; then
        printf "
    link: ${KIS_INSTALL_DIR}/bin/qmake-qt5 missing!
    It probably means ext_qt failed!!
    check, fix and rerun!\n"
        exit 1
    fi

    # for python
    cmake_3rdparty \
        ext_sip \
        ext_pyqt

    cmake_3rdparty ext_libheif

    cmake_3rdparty \
        ext_extra_cmake_modules \
        ext_kconfig \
        ext_kwidgetsaddons \
        ext_kcompletion \
        ext_kcoreaddons \
        ext_kguiaddons \
        ext_ki18n \
        ext_kitemmodels \
        ext_kitemviews \
        ext_kimageformats \
        ext_kwindowsystem \
        ext_quazip

    cmake_3rdparty ext_seexpr
    cmake_3rdparty ext_mypaint
    cmake_3rdparty ext_webp
    cmake_3rdparty ext_jpegxl
    cmake_3rdparty ext_xsimd


    ## All builds done, creating a new install onlydeps install dir
    dir_clean "${KIS_INSTALL_DIR}.onlydeps"
    log "Copying ${KIS_INSTALL_DIR} to ${KIS_INSTALL_DIR}.onlydeps"
    cp -aP "${KIS_INSTALL_DIR}" "${KIS_INSTALL_DIR}.onlydeps"
    print_msg "Build Finished!"
}


#not tested
set_krita_dirs() {
    if [[ -n ${1} ]]; then
        KIS_BUILD_DIR=${BUILDROOT}/b_${1}
        KIS_INSTALL_DIR=${BUILDROOT}/i_${1}
        KIS_SRC_DIR=${BUILDROOT}/src_${1}
    fi
}
# build_krita
# run cmake krita
build_krita () {
    if [[ -z ${OSXBUILD_CLEAN} ]]; then
        log "Deleting ${KIS_BUILD_DIR}"
        dir_clean "${KIS_BUILD_DIR}"
    else
        if [[ -e "${KIS_INSTALL_DIR}.onlydeps" && -d "${KIS_INSTALL_DIR}.onlydeps" ]]; then
            print_msg "Found ${KIS_INSTALL_DIR}.onlydeps"
            log "==== manually copy onlydeps to ${KIS_INSTALL_DIR} if you need a fresh build"
        fi
    fi

    export DYLD_FRAMEWORK_PATH=${FRAMEWORK_PATH}
    echo ${KIS_BUILD_DIR}
    echo ${KIS_INSTALL_DIR}
    log_cmd check_dir_path ${KIS_BUILD_DIR}
    cd ${KIS_BUILD_DIR}

    if [ -z "${KRITA_BRANDING}" ]; then
        # determine the channel for branding
        if [ "${JOB_NAME}" == "Krita_Nightly_MacOS_Build" ]; then
            KRITA_BRANDING="Next"
        elif [ "${JOB_NAME}" == "Krita_Stable_MacOS_Build" ]; then
            KRITA_BRANDING="Plus"
        else
            KRITA_BRANDING=""
        fi
    fi

    declare -a CMAKE_CMD
    CMAKE_CMD=(cmake "${KIS_SRC_DIR}"
        -G "\"${OSXBUILD_GENERATOR}\""
        -DFOUNDATION_BUILD=ON
        -DBRANDING="${KRITA_BRANDING}"
        -DBoost_INCLUDE_DIR="${KIS_INSTALL_DIR}/include"
        -DCMAKE_INSTALL_PREFIX="${KIS_INSTALL_DIR}"
        -DCMAKE_PREFIX_PATH="${KIS_INSTALL_DIR}"
        -DDEFINE_NO_DEPRECATED=1
        -DBUILD_TESTING="${OSXBUILD_TESTING}"
        -DHIDE_SAFE_ASSERTS"=${OSXBUILD_HIDE_SAFEASSERTS}"
        -DFETCH_TRANSLATIONS=ON
        -DKRITA_ENABLE_PCH=off
        -DKDE_INSTALL_BUNDLEDIR="${KIS_INSTALL_DIR}/bin"
        -DPYQT_SIP_DIR_OVERRIDE="${KIS_INSTALL_DIR}/share/sip/"
        -DCMAKE_BUILD_TYPE="${OSXBUILD_TYPE}"
        -DCMAKE_OSX_DEPLOYMENT_TARGET=10.13
        -DPYTHON_INCLUDE_DIR="${KIS_INSTALL_DIR}/lib/Python.framework/Headers"
        -DCMAKE_OSX_ARCHITECTURES="${OSX_ARCHITECTURES}"
        -DMACOS_UNIVERSAL="${OSXBUILD_UNIVERSAL}"
        )

    # hack:: Jenkins runs in x86_64 env, force run cmake in arm64 env.
    printf -v CMAKE_CMD_STRING '%s ' "${CMAKE_CMD[@]}"
    if [[ ${OSXBUILD_UNIVERSAL} ]]; then
        log_cmd env /usr/bin/arch -arm64 /bin/zsh -c "${CMAKE_CMD_STRING}"
    else
        log_cmd /bin/zsh -c "${CMAKE_CMD_STRING}"
    fi

    print_if_error "Configuration error! ${filename}" "exit"

    # copiling phase
    log_cmd cmake --build . -j${MAKE_THREADS}
    print_if_error "Krita compilation failed! ${filename}" "exit"

    # compile integrations
    if test "${OSTYPE}" == "darwin*"; then
        cd "${KIS_BUILD_DIR}/krita/integration/kritaquicklook"
        cmake --build . -j${MAKE_THREADS}
    fi
}

build_krita_tarball () {
    filename="$(basename ${1})"
    KIS_CUSTOM_BUILD="${BUILDROOT}/releases/${filename%.tar.gz}"
    print_msg "Tarball BUILDROOT is ${KIS_CUSTOM_BUILD}"

    filename_dir=$(dirname "${1}")
    cd "${filename_dir}"
    file_abspath="$(pwd)/${1##*/}"

    mkdir "${KIS_CUSTOM_BUILD}" 2> /dev/null
    cd "${KIS_CUSTOM_BUILD}"

    mkdir "src" "build" 2> /dev/null
    log_cmd tar -xzf "${file_abspath}" --strip-components=1 --directory "src"

    print_if_error "Failed untar of ${filename}" "exit"

    KIS_BUILD_DIR="${KIS_CUSTOM_BUILD}/build"
    KIS_SRC_DIR="${KIS_CUSTOM_BUILD}/src"

    build_krita

    print_msg "Build done!"
}

install_krita () {
    # custom install provided
    if [[ -n "${1}" ]]; then
        KIS_BUILD_DIR="${1}"
    fi

    # Delete any "krita" named file in install
    # this helps avoid double versioned libraries
    log "About to delete krita libs from ${KIS_INSTALL_DIR}"
    waiting_fixed "Deleting files in 5 seconds" 5
    find ${KIS_INSTALL_DIR} -type d -name "*krita*" | xargs -I FILE  rm -rf FILE
    find ${KIS_INSTALL_DIR}  \( -type f -or -type l \) -name "*krita*" | xargs -P4 -I FILE rm FILE

    print_msg "Install krita from ${KIS_BUILD_DIR}"
    log_cmd check_dir_path ${KIS_BUILD_DIR}

    cd "${KIS_BUILD_DIR}"
    osxbuild_error="${?}"
    print_if_error "could not cd to ${KIS_BUILD_DIR}" "exit"

    cmake --install .

    # compile integrations
    if test ${OSTYPE} == "darwin*"; then
        cd ${KIS_BUILD_DIR}/krita/integration
        cmake --install .
    fi
}

build_plugins () {
    if [[ -z ${OSXBUILD_CLEAN} ]]; then
        dir_clean "${KIS_PLUGIN_BUILD_DIR}"
    fi

    print_msg "building in ${KIS_PLUGIN_BUILD_DIR}"

    log "$(check_dir_path ${KIS_PLUGIN_BUILD_DIR})"
    log "$(check_dir_path ${KIS_DOWN_DIR})"
    log "$(check_dir_path ${KIS_INSTALL_DIR})"

    cd ${KIS_PLUGIN_BUILD_DIR}

    log_cmd cmake ${KIS_SRC_DIR}/3rdparty_plugins/ \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=10.12 \
        -DCMAKE_INSTALL_PREFIX=${KIS_INSTALL_DIR} \
        -DCMAKE_PREFIX_PATH:PATH=${KIS_INSTALL_DIR} \
        -DEXTERNALS_DOWNLOAD_DIR=${KIS_DOWN_DIR} \
        -DINSTALL_ROOT=${KIS_INSTALL_DIR}


    print_msg "finished plugins build setup"

    cmake_3rdparty_plugins \
        ext_gmic \

    print_msg "Build Finished!"
}

get_directory_fromargs() {
    local OSXBUILD_DIR=""
    for arg in "${@}"; do
        if [[ -d "${arg}" ]]; then
            OSXBUILD_DIR="${arg}"
            continue
        fi
    done
    echo "${OSXBUILD_DIR}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

####      Universal ARM x86_64 build functions and parameters     #####

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

DEPBUILD_X86_64_DIR="${BUILDROOT}/i.x86_64"
DEPBUILD_ARM64_DIR="${BUILDROOT}/i.arm64"
DEPBUILD_FATBIN_DIR="${BUILDROOT}/i.universal"

build_x86_64 () {
    log "building builddeps_x86"
    # first set terminal to arch
    if [[ ${#@} > 0 ]]; then
        for pkg in ${@:1:${#@}}; do
            env /usr/bin/arch -x86_64 /bin/zsh -c "${BUILDROOT}/krita/packaging/macos/osxbuild.sh builddeps --dirty ${pkg}"
        done
    else
        env /usr/bin/arch -x86_64 /bin/zsh -c "${BUILDROOT}/krita/packaging/macos/osxbuild.sh builddeps"
    fi
    osxbuild_error="${?}"
    print_if_error "Error while building x86_64 deps" "exit"

    rsync -aq "${KIS_INSTALL_DIR}/" "${DEPBUILD_X86_64_DIR}"
}


build_arm64 () {
    log "building builddeps_arm64"

    # force arm64 build even in x86_64 envs 
    if [[ ${#@} > 0 ]]; then
        for pkg in ${@:1:${#@}}; do
            env /usr/bin/arch -arm64 /bin/zsh -c "${BUILDROOT}/krita/packaging/macos/osxbuild.sh builddeps --dirty ${pkg}"
        done
    else
        env /usr/bin/arch -arm64 /bin/zsh -c "${BUILDROOT}/krita/packaging/macos/osxbuild.sh builddeps"
    fi
    osxbuild_error="${?}"
    print_if_error "Error while building arm64 deps" "exit"

    rsync -aq "${KIS_INSTALL_DIR}/" "${DEPBUILD_ARM64_DIR}"
}

consolidate_universal_binaries () {
    for f in "${@}"; do
        # Only try to consolidate Mach-O and static libs
        if [[ -n $(file ${f} | grep "Mach-O") || "${f:(-2)}" = ".a" ]]; then
            # echo "${BUILDROOT}/${DEPBUILD_X86_64_DIR}/${f##*test-i/}"
            LIPO_OUTPUT=$(lipo -info ${f} | grep Non-fat 2> /dev/null)
            if [[ -n ${LIPO_OUTPUT} ]]; then
                if [[ -f "${DEPBUILD_X86_64_DIR}/${f##*${DEPBUILD_FATBIN_DIR}/}" ]]; then
                    log "creating universal binary -- ${f##*${DEPBUILD_FATBIN_DIR}/}"
                    lipo -create "${f}" "${DEPBUILD_X86_64_DIR}/${f##*${DEPBUILD_FATBIN_DIR}/}" -output "${f}"
                fi
            fi
            # log "ignoring ${f}"
        fi
    done

}

prebuild_cleanup() {
    # assume if an argument is given is a package name, do not erase install dir
    if [[ ${#@} > 0 ]]; then
        rsync -aq "${KIS_INSTALL_DIR}/" "${BUILDROOT}/i.temp"
    fi
    rm -rf "${DEPBUILD_FATBIN_DIR}" "${DEPBUILD_X86_64_DIR}" "${DEPBUILD_ARM64_DIR}"
}

postbuild_cleanup() {
    log "consolidating non-fat binaries and files"
    rsync -rlptgoq --ignore-existing "${DEPBUILD_X86_64_DIR}/" "${DEPBUILD_FATBIN_DIR}"
    rm -rf "${KIS_INSTALL_DIR}"
    rsync -aq "${DEPBUILD_FATBIN_DIR}/" "${KIS_INSTALL_DIR}"
    log "consolitating done! Build installed to ${KIS_INSTALL_DIR}"
}

universal_plugin_build() {
    DEPBUILD_X86_64_DIR="${BUILDROOT}/i_plug.x86_64"
    DEPBUILD_ARM64_DIR="${BUILDROOT}/i_plug.arm64"
    # DEPBUILD_FATBIN_DIR="${BUILDROOT}/i.universal"

    # assume i is universal but i.universal has to exist
    if [[ ! -d "${DEPBUILD_FATBIN_DIR}" ]]; then
        log "WARNING no i.universal install dir found! Make sure universal build finished properly"
        log "If you get errors building plugins this is likely the error."
    fi

    rsync -rlptgoq --ignore-existing "${KIS_INSTALL_DIR}/" "${DEPBUILD_FATBIN_DIR}/"

    log "building plugins_x86"
    env /usr/bin/arch -x86_64 /bin/zsh -c "${BUILDROOT}/krita/packaging/macos/osxbuild.sh buildplugins"
    osxbuild_error="${?}"
    print_if_error "Error while building x86_64 plugins" "exit"
    rsync -aq "${KIS_INSTALL_DIR}/" "${DEPBUILD_X86_64_DIR}"

    log "building plugins_arm64"
    # force arm64 build even in x86_64 envs
    env /usr/bin/arch -arm64 /bin/zsh -c "${BUILDROOT}/krita/packaging/macos/osxbuild.sh buildplugins"
    osxbuild_error="${?}"
    print_if_error "Error while building arm64 plugins" "exit"
    rsync -aq "${KIS_INSTALL_DIR}/" "${DEPBUILD_ARM64_DIR}"

    # sync files to universal install dir.
    rsync -aq "${DEPBUILD_ARM64_DIR}/" "${DEPBUILD_FATBIN_DIR}"
    consolidate_universal_binaries $(find "${DEPBUILD_FATBIN_DIR}" -type f)
    postbuild_cleanup

}


# # # # # # # # # # # # # # # # # # #

####     Script main routine    #####

# # # # # # # # # # # # # # # # # # #
print_usage () {
    printf "USAGE: osxbuild.sh <buildstep> [pkg|file]\n"
    printf "BUILDSTEPS:\t\t"
    printf "\n builddeps \t\t Run cmake step for 3rd party dependencies, optionally takes a [pkg] arg"
    printf "\n fixboost \t\t Fixes broken boost \@rpath on OSX"
    printf "\n build \t\t\t Builds krita"
    printf "\n buildtarball \t\t Builds krita from provided [file] tarball"
    printf "\n clean \t\t\t Removes build and install directories to start fresh"
    printf "\n install \t\t Installs krita. Optionally accepts a [build dir] as argument
    \t\t\t this will install krita from given directory"
    printf "\n buildinstall \t\t Build and Installs krita, running fixboost after installing"
    printf "\n"
    printf "OPTIONS:\t\t"
    printf "\n \t --dirty \t [build/install] (old default) Keep old build directories before build to start fresh"
    printf "\n \t --debug \t [build] Build in Debug mode"
    printf "\n \t --tests \t [build] Build tests"
    printf "\n \t --showasserts \t [build] Do not hide asserts"
    printf "\n \t --universal \t [build] (arm only) Build universal binary files."
    printf "\n"
    printf "\n \t --install_tarball \n \t\t\t [buildtarball] Install just built tarball file."
    printf "\n"
}

script_run() {
    if [[ ${#} -eq 0 ]]; then
        echo "ERROR: No option given!"
        print_usage
        exit 1
    fi

    if [[ ${1} = "builddeps" ]]; then
        if [[ ${OSXBUILD_UNIVERSAL} ]]; then
            prebuild_cleanup ${@:2}
            build_x86_64 ${@:2}

            build_arm64 "${@:2}"

            rsync -aq ${DEPBUILD_ARM64_DIR}/ ${DEPBUILD_FATBIN_DIR}
            consolidate_universal_binaries $(find "${DEPBUILD_FATBIN_DIR}" -type f)

            postbuild_cleanup

        else
            if [[ -z ${OSXBUILD_CLEAN} ]]; then
                dir_clean "${KIS_INSTALL_DIR}"
                dir_clean "${KIS_TBUILD_DIR}"
            fi
            build_3rdparty "${@:2}"

        fi

    elif [[ ${1} = "build" ]]; then
        OSXBUILD_DIR=$(get_directory_fromargs "${@:2}")

        build_krita "${OSXBUILD_DIR}"
        exit

    elif [[ ${1} = "buildplugins" ]]; then
        if [[ ${OSXBUILD_UNIVERSAL} ]]; then
            universal_plugin_build "${@:2}"
        else
            build_plugins "${@:2}"
        fi
        exit

    elif [[ ${1} = "buildtarball" ]]; then
        # uncomment line to optionally change
        # install directory providing a third argument
        # This is not on by default as build success requires all
        # deps installed in the given dir beforehand.
        # KIS_INSTALL_DIR=${3}

        if [[ -f "${2}" && "${2:(-7)}" == ".tar.gz" ]]; then
            TARBALL_FILE="${2}"
            build_krita_tarball "${TARBALL_FILE}"

            if [[ -n "${OSXBUILD_TARBALLINSTALL}" ]]; then
                install_krita "${KIS_BUILD_DIR}"
            else
                print_msg "to install run
osxbuild.sh install ${KIS_BUILD_DIR}"
            fi
            exit
        else
            log "File not a tarball tar.gz file"
        fi
        

    elif [[ ${1} = "clean" ]]; then
        # remove all build and install directories to start
        # a fresh install. this no different than using rm directly
        dir_clean "${KIS_TBUILD_DIR}"
        dir_clean "${$KIS_BUILD_DIR}"
        dir_clean "${KIS_INSTALL_DIR}"
        exit

    elif [[ ${1} = "install" ]]; then
        OSXBUILD_DIR=$(get_directory_fromargs "${@:2}")

        install_krita "${OSXBUILD_DIR}"
        
        if [[ ${OSXBUILD_UNIVERSAL} ]]; then
            universal_plugin_build "${@:2}"
        else
            build_plugins "${OSXBUILD_DIR}"
        fi

    elif [[ ${1} = "buildinstall" ]]; then
        OSXBUILD_DIR=$(get_directory_fromargs "${@:2}")

        build_krita "${OSXBUILD_DIR}"
        install_krita "${OSXBUILD_DIR}"

        if [[ ${OSXBUILD_UNIVERSAL} ]]; then
            universal_plugin_build "${@:2}"
        else
            build_plugins "${OSXBUILD_DIR}"
        fi

    elif [[ ${1} = "test" ]]; then
        ${KIS_INSTALL_DIR}/bin/krita.app/Contents/MacOS/krita

    else
        echo "Option ${1} not supported"
        print_usage
        exit 1
    fi
}

script_run ${parsed_args}
