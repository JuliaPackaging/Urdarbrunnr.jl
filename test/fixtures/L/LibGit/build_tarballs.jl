using BinaryBuilder

name = "LibGit"
version = v"2.3.4"

sources = [
    GitSource("https://github.com/example/libgit.git",
              "0123456789abcdef0123456789abcdef01234567"),
    FileSource("https://example.com/static/config-file.txt",
               "aaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999",
               "config-file.txt"),
]

script = raw"""
cd $WORKSPACE/srcdir/libgit
./configure --prefix=${prefix}
make -j${nproc} install
"""

platforms = supported_platforms()
products = [LibraryProduct("libgit", :libgit)]
dependencies = Dependency[]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)
