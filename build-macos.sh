#!/bin/bash
set -euo pipefail

NPROC=$(sysctl -n hw.ncpu)

# Install dependencies
brew install cmake boost protobuf

# Build SEAL 4.1.2
git clone -b v4.1.2 --depth 1 https://github.com/microsoft/SEAL.git /tmp/SEAL
cd /tmp/SEAL
sed -i '' '9a\
#include <mutex>
' native/src/seal/util/locks.h
cmake -DSEAL_THROW_ON_TRANSPARENT_CIPHERTEXT=OFF -DSEAL_BUILD_DEPS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -B build .
cmake --build build -j"$NPROC"
sudo cmake --install build

# Clone and patch EVA
git clone https://github.com/microsoft/EVA.git /tmp/EVA
cd /tmp/EVA
git submodule update --init

# Upgrade pybind11 for Python 3.12+
cd third_party/pybind11 && git fetch --tags && git checkout v2.13.6 && cd ../..

# Patch for SEAL 4.x
sed -i '' 's/find_package(SEAL 3.6/find_package(SEAL 4.1/' CMakeLists.txt

# Patch for missing <cstdint>
sed -i '' '7a\
#include <cstdint>
' eva/ckks/ckks_config.h

# Build EVA
cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -B build .
cmake --build build -j"$NPROC"

# Build wheel (use find_namespace_packages to include eva.std)
pip install --break-system-packages psutil wheel setuptools
sed -i '' 's/find_packages/find_namespace_packages/' build/python/setup.py
cd build/python && python3 setup.py bdist_wheel --dist-dir=/tmp/EVA/dist
cd /tmp/EVA

# Run tests
pip install --break-system-packages -r examples/requirements.txt
pip install --break-system-packages dist/*.whl
python3 tests/all.py

echo "Wheel built successfully:"
ls /tmp/EVA/dist/*.whl
