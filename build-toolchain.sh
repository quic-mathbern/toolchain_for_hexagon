#!/bin/bash -x

#  Copyright (c) 2021, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

STAMP=${1-$(date +"%Y_%b_%d")}

set -euo pipefail
set -x

build_llvm_clang() {
	cd ${BASE}
	mkdir -p obj_llvm
	cd obj_llvm

	CC=clang CXX=clang++ cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/ \
		-DLLVM_CCACHE_BUILD:BOOL=OFF \
		-DLLVM_ENABLE_LLD:BOOL=ON \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_ENABLE_TERMINFO:BOOL=OFF \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DLLVM_ENABLE_PIC:BOOL=OFF \
		-DLLVM_TARGETS_TO_BUILD:STRING="Hexagon" \
		-DLLVM_PYTHON_EXECUTABLE:STRING=$(which python3.6) \
		-DLLVM_DEFAULT_TARGET_TRIPLE:STRING="hexagon-unknown-musl-linux" \
		-DCLANG_DEFAULT_CXX_STDLIB:STRING="libc++" \
		-DCLANG_DEFAULT_OBJCOPY:STRING="llvm-objcopy" \
		-DCLANG_DEFAULT_LINKER:STRING="lld" \
		-DDEFAULT_SYSROOT:STRING="../target/hexagon-unknown-linux-musl/" \
		-DLLVM_ENABLE_PROJECTS:STRING="clang;lld" \
		../llvm-project/llvm
 	ninja all install
	cd ${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin
	ln -sf clang hexagon-unknown-linux-musl-clang
	ln -sf clang++ hexagon-unknown-linux-musl-clang++
	ln -sf llvm-ar hexagon-unknown-linux-musl-ar
	ln -sf llvm-objdump hexagon-unknown-linux-musl-objdump
	ln -sf llvm-objcopy hexagon-unknown-linux-musl-objcopy
	ln -sf llvm-readelf hexagon-unknown-linux-musl-readelf
	ln -sf llvm-ranlib hexagon-unknown-linux-musl-ranlib
}

build_clang_rt() {
	cd ${BASE}
	mkdir -p obj_clang_rt
	cd obj_clang_rt
	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CONFIG_PATH:PATH=${TOOLCHAIN_BIN}/llvm-config \
		-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR:BOOL=OFF \
		-DCMAKE_ASM_FLAGS:STRING="-G0 -mlong-calls -fno-pic" \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCOMPILER_RT_EMULATOR:STRING="${TOOLCHAIN_BIN}/qemu_wrapper.sh" \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCMAKE_C_COMPILER_FORCED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		-DCOMPILER_RT_BUILD_BUILTINS:BOOL=ON \
		-DCOMPILER_RT_BUILTINS_ENABLE_PIC:BOOL=OFF \
		-DCMAKE_SIZEOF_VOID_P=4 \
		-DCOMPILER_RT_OS_DIR= \
		-DCAN_TARGET_hexagon=1 \
		-DCAN_TARGET_x86_64=0 \
		-DCOMPILER_RT_SUPPORTED_ARCH=hexagon \
		../llvm-project/compiler-rt
	ninja install-builtins
}



config_kernel() {
	cd ${BASE}
	mkdir obj_linux
	cd linux
	make O=../obj_linux ARCH=hexagon \
		CROSS_COMPILE=hexagon-unknown-linux-musl- \
		CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/clang \
		AS=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/clang \
		LD=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/ld.lld \
		LLVM=1 \
		LLVM_IAS=1 \
		KBUILD_VERBOSE=1 comet_defconfig
}

build_kernel_headers() {
	cd ${BASE}
	cd linux
	make mrproper
	cd ${BASE}
	cd obj_linux
	make \
	        ARCH=hexagon \
	       	CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/clang \
		INSTALL_HDR_PATH=${HEX_TOOLS_TARGET_BASE} \
		V=1 \
		headers_install

}

build_musl_headers() {
	cd ${BASE}
	cd musl
	make clean

	CC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/hexagon-unknown-linux-musl-clang \
		CROSS_COMPILE=hexagon-unknown-linux-musl \
	       	LIBCC=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl/lib/libclang_rt.builtins-hexagon.a \
		CROSS_CFLAGS="-G0 -O0 -mv65 -fno-builtin  --target=hexagon-unknown-linux-musl" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make CROSS_COMPILE= install-headers

	cd ${HEX_SYSROOT}/..
	ln -sf hexagon-unknown-linux-musl hexagon
}

build_musl() {
	cd ${BASE}
	cd musl
	make clean

	CROSS_COMPILE=hexagon-unknown-linux-musl- \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
	       	CC=clang \
	       	LIBCC=${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.builtins-hexagon.a \
		CFLAGS="${MUSL_CFLAGS}" \
		./configure --target=hexagon --prefix=${HEX_TOOLS_TARGET_BASE}
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make -j CROSS_COMPILE= install
	cd ${HEX_TOOLS_TARGET_BASE}/lib
	ln -sf libc.so ld-musl-hexagon.so
	ln -sf ld-musl-hexagon.so ld-musl-hexagon.so.1
	mkdir -p ${HEX_TOOLS_TARGET_BASE}/../lib
	cd ${HEX_TOOLS_TARGET_BASE}/../lib
	ln -sf ../usr/lib/ld-musl-hexagon.so.1
}


build_libs() {
	cd ${BASE}
	mkdir -p obj_libs
	cd obj_libs
	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CONFIG_PATH:PATH=${TOOLCHAIN_BIN}/llvm-config \
		-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR:BOOL=OFF \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_EXE_LINKER_FLAGS:STRING="-lclang_rt.builtins-hexagon -nostdlib" \
		-DCMAKE_SHARED_LINKER_FLAGS:STRING="-lclang_rt.builtins-hexagon -nostdlib" \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_CXX_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang++" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DLIBCXX_INCLUDE_BENCHMARKS:BOOL=OFF \
		-DLLVM_ENABLE_RUNTIMES:STRING="libcxx;libcxxabi;libunwind;compiler-rt" \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DLIBCXX_HAS_MUSL_LIBC:BOOL=ON \
		-DLIBCXX_INCLUDE_TESTS:BOOL=OFF \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
		-DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		../llvm-project/runtimes
	ninja -v install-unwind
	ninja -v install-cxxabi
	ninja -v install-cxx
	ninja -v install-compiler-rt
}

build_sanitizers() {
	cd ${BASE}
	mkdir -p obj_san
	cd obj_san
	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_CONFIG_PATH:PATH=${TOOLCHAIN_BIN}/llvm-config \
		-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR:BOOL=OFF \
		-DCMAKE_ASM_FLAGS:STRING="-G0 -mlong-calls" \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_CXX_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang++" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCOMPILER_RT_EMULATOR:STRING="${TOOLCHAIN_BIN}/qemu_wrapper.sh" \
		-DCOMPILER_RT_CAN_EXECUTE_TESTS:BOOL=ON \
		-DCMAKE_INSTALL_PREFIX:PATH=${HEX_TOOLS_TARGET_BASE} \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCMAKE_C_COMPILER_FORCED:BOOL=ON \
		-DCMAKE_CXX_COMPILER_FORCED:BOOL=ON \
		-DCOMPILER_RT_BUILD_BUILTINS:BOOL=OFF \
		-DCMAKE_SIZEOF_VOID_P=4 \
		-DCOMPILER_RT_OS_DIR= \
		-DCAN_TARGET_hexagon=1 \
		-DCAN_TARGET_x86_64=0 \
		-DCOMPILER_RT_SUPPORTED_ARCH=hexagon \
		../llvm-project/compiler-rt
	ninja install-compiler-rt
}


build_qemu() {
	cd ${BASE}
	mkdir -p obj_qemu
	cd obj_qemu
	CC=$(which gcc) \
	../qemu/configure --disable-fdt --disable-capstone --disable-guest-agent \
	                  --disable-containers \
	                  --python=$(which python3.8) \
		--target-list=hexagon-linux-user --prefix=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu \

#	--cc=clang \
#	--cross-prefix=hexagon-unknown-linux-musl-
#	--cross-cc-hexagon="hexagon-unknown-linux-musl-clang" \
#		--cross-cc-cflags-hexagon="-mv67 --sysroot=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl"

	make -j
	make -j install

	cat <<EOF > ./qemu_wrapper.sh
#!/bin/bash

set -euo pipefail

export QEMU_LD_PREFIX=${HEX_TOOLS_TARGET_BASE}

exec ${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/qemu-hexagon \$*
EOF
	cp ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/
	chmod +x ./qemu_wrapper.sh ${TOOLCHAIN_BIN}/qemu_wrapper.sh
}

purge_builds() {
	rm -rf ${BASE}/obj_*/
}

set +x

TOOLCHAIN_INSTALL_REL=${TOOLCHAIN_INSTALL}
TOOLCHAIN_INSTALL=$(readlink -f ${TOOLCHAIN_INSTALL})
TOOLCHAIN_BIN=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin
HEX_SYSROOT=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl
HEX_TOOLS_TARGET_BASE=${HEX_SYSROOT}/usr
ROOT_INSTALL_REL=${ROOT_INSTALL}
ROOTFS=$(readlink -f ${ROOT_INSTALL})
RESULTS_DIR_=${ARTIFACT_BASE}/${ARTIFACT_TAG}
mkdir -p ${RESULTS_DIR_}
RESULTS_DIR=$(readlink -f ${RESULTS_DIR_})

if [[ ! -d ${RESULTS_DIR} ]]; then
    echo err results dir "${RESULTS_DIR}" not found or not a dir
    exit 3
fi

REL_NAME=$(basename ${TOOLCHAIN_INSTALL_REL})
BASE=$(readlink -f ${PWD})

if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    echo toolchain will be placed in ${RESULTS_DIR}/${REL_NAME}.tar.xz
    echo creating empty file there as a test:
    echo '' > ${RESULTS_DIR}/${REL_NAME}.tar.xz
fi

ccache --show-stats


MUSL_CFLAGS="-G0 -O0 -mv65 -fno-builtin -mlong-calls --target=hexagon-unknown-linux-musl"

# Workaround, 'C()' macro results in switch over bool:
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-switch-bool"
# Workaround, this looks like a bug/incomplete feature in the
# hexagon compiler backend:
MUSL_CFLAGS="${MUSL_CFLAGS} -Wno-unsupported-floating-point-opt"

which clang
clang --version
ninja --version
cmake --version
python3.6 --version

build_llvm_clang
ccache --show-stats
config_kernel
build_kernel_headers
build_musl_headers
build_clang_rt
build_musl

build_libs
build_sanitizers

build_qemu

cd ${BASE}
if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
#   XZ_OPT="-e9T0" tar cJf ${RESULTS_DIR}/${REL_NAME}.tar.xz -C $(dirname ${TOOLCHAIN_INSTALL_REL}) ${REL_NAME}
    tar c -C $(dirname ${TOOLCHAIN_INSTALL_REL}) ${REL_NAME} | xz -e9T0 > ${RESULTS_DIR}/${REL_NAME}.tar.xz
    cd ${RESULTS_DIR}
    sha256sum ${REL_NAME}.tar.xz | tee ${REL_NAME}.tar.xz.sha256
fi
