# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "Zstd"
version = v"1.5.6"

# Collection of sources required to complete build
sources = [
    ArchiveSource("https://github.com/facebook/zstd/releases/download/v$(version)/zstd-$(version).tar.gz",
                  "8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1"),
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/zstd-*/
make -j${nproc} CC=${CC}
make install PREFIX=${prefix}
install_license LICENSE
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = supported_platforms()

# The products that we will ensure are always built
products = [
    LibraryProduct("libzstd", :libzstd),
    ExecutableProduct("zstd", :zstd),
]

# Dependencies that must be installed before this package can be built
dependencies = Dependency[]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.6")
