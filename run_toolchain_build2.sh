#!/bin/bash


CC=/opt/clang-latest/bin/clang \
CXX=/opt/clang-latest/bin/clang++ \
RESULTS_DIR=${PWD}/results \
MAKE_TARBALLS=0 \
ARTIFACT_BASE=${PWD}/artifacts \
ARTIFACT_TAG=none  \
ROOT_INSTALL=${PWD}/rootfs \
TOOLCHAIN_INSTALL=${PWD}/install \
	./build-toolchain-dist.sh
