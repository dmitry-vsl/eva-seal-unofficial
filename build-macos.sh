#!/bin/bash
set -euo pipefail

NPROC=$(sysctl -n hw.ncpu)

# Install dependencies
brew install cmake boost protobuf llvm python@3.10 python@3.11 python@3.12 python@3.13 python@3.14

# Build SEAL 4.1.2
git clone -b v4.1.2 --depth 1 https://github.com/microsoft/SEAL.git /tmp/SEAL
cd /tmp/SEAL
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

# Remove hardcoded numa link (not available on macOS)
sed -i '' 's/Galois::shmem numa/Galois::shmem/' eva/CMakeLists.txt

# Patch for missing <cstdint>
sed -i '' '7a\
#include <cstdint>
' eva/ckks/ckks_config.h

# Patch cpu_affinity() which is not available on macOS
sed -i '' 's/len(psutil.Process().cpu_affinity())/psutil.cpu_count(logical=False)/' python/eva/__init__.py

# Build wheels for all Python versions
for pyver in 3.10 3.11 3.12 3.13 3.14; do
  echo "=== Building for Python $pyver ==="

  PYTHON_BIN="$(brew --prefix python@$pyver)/bin/python$pyver"

  # Clean previous build
  rm -rf build

  # Build EVA with Galois multicore support
  cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DUSE_GALOIS=ON \
        -DLLVM_DIR="$(brew --prefix llvm)/lib/cmake/llvm" \
        -DPython_EXECUTABLE="$PYTHON_BIN" \
        -B build .
  cmake --build build -j"$NPROC"

  # Set up venv for building and testing
  rm -rf /tmp/eva-venv
  "$PYTHON_BIN" -m venv /tmp/eva-venv
  source /tmp/eva-venv/bin/activate

  # Build wheel
  pip install psutil wheel setuptools
  sed -i '' 's/find_packages/find_namespace_packages/' build/python/setup.py
  sed -i '' "s/name='eva'/name='eva-seal-unofficial'/" build/python/setup.py
  sed -i '' "s|description='Compiler for the Microsoft SEAL homomorphic encryption library'|description='Unofficial builds of Microsoft EVA',\\
    long_description='Unofficial builds of [Microsoft EVA](https://github.com/microsoft/EVA). Built from [eva-seal-unofficial](https://github.com/dmitry-vsl/eva-seal-unofficial).',\\
    long_description_content_type='text/markdown',\\
    url='https://github.com/dmitry-vsl/eva-seal-unofficial'|" build/python/setup.py
  cd build/python && python setup.py bdist_wheel --dist-dir=/tmp/EVA/dist && cd /tmp/EVA

  # Run tests
  pip install -r examples/requirements.txt
  pip install dist/*cp${pyver/./}*.whl
  python tests/all.py

  deactivate
done

echo "Wheels built successfully:"
ls /tmp/EVA/dist/*.whl
