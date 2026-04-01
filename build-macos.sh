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
cmake -DSEAL_THROW_ON_TRANSPARENT_CIPHERTEXT=OFF -DSEAL_USE_ZLIB=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -B build .
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

# Patch cpu_affinity() which is not available on macOS
sed -i '' 's/len(psutil.Process().cpu_affinity())/psutil.cpu_count(logical=False)/' python/eva/__init__.py

# Build EVA
cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -B build .
cmake --build build -j"$NPROC"

# Set up venv for building and testing
python3 -m venv /tmp/eva-venv
source /tmp/eva-venv/bin/activate

# Build wheel (use find_namespace_packages to include eva.std)
pip install psutil wheel setuptools
sed -i '' 's/find_packages/find_namespace_packages/' build/python/setup.py
cd build/python && python3 setup.py bdist_wheel --dist-dir=/tmp/EVA/dist
cd /tmp/EVA

# Run tests
pip install -r examples/requirements.txt
pip install dist/*.whl
python3 tests/all.py

echo "Wheel built successfully:"
ls /tmp/EVA/dist/*.whl
