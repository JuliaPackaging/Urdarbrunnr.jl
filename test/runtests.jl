using Urdarbrunnr
using Test

const FIXTURES = joinpath(@__DIR__, "fixtures")

@testset "Urdarbrunnr" begin

@testset "parse_recipe: ArchiveSource recipe" begin
    recipe = parse_recipe(joinpath(FIXTURES, "Z", "Zstd", "build_tarballs.jl"))
    @test recipe.name == "Zstd"
    @test recipe.version == v"1.5.6"
    @test length(recipe.sources) == 1
    src = only(recipe.sources)
    @test src.kind == :ArchiveSource
    @test src.url == "https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz"
    @test src.hash == "8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1"
end

@testset "parse_recipe: GitSource + static FileSource" begin
    recipe = parse_recipe(joinpath(FIXTURES, "L", "LibGit", "build_tarballs.jl"))
    @test recipe.name == "LibGit"
    @test recipe.version == v"2.3.4"
    @test [s.kind for s in recipe.sources] == [:GitSource, :FileSource]
    @test recipe.sources[1].url == "https://github.com/example/libgit.git"
    @test recipe.sources[2].url == "https://example.com/static/config-file.txt"
end

@testset "parse_recipe: rejects what it can't handle" begin
    @test_throws ErrorException Urdarbrunnr.parse_recipe_text("""
        name = "Foo"
        version = VersionNumber(get(ENV, "FOO_VERSION", "1.0.0"))
        sources = []
        """)
    @test_throws ErrorException Urdarbrunnr.parse_recipe_text("""
        name = "Foo"
        version = v"1.0.0"
        sources = [ArchiveSource("https://example.com/foo.tar.gz", some_hash_variable)]
        """)
    @test_throws ErrorException Urdarbrunnr.parse_recipe_text("""
        version = v"1.0.0"
        """) # no name
end

@testset "render_url" begin
    recipe = parse_recipe(joinpath(FIXTURES, "Z", "Zstd", "build_tarballs.jl"))
    src = only(recipe.sources)
    @test render_url(src.url_expr; version=v"1.5.7", name="Zstd") ==
        "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz"
    # Plain strings pass through untouched
    @test render_url("https://example.com/x.tar.gz"; version=v"9.9.9") ==
        "https://example.com/x.tar.gz"
    # Major/minor style interpolation
    expr = Meta.parse("\"https://example.com/foo-\$(version.major).\$(version.minor).tar.gz\"")
    @test render_url(expr; version=v"3.4.5") == "https://example.com/foo-3.4.tar.gz"
    # References to unknown variables fail loudly
    bad = Meta.parse("\"https://example.com/\$(mystery)/foo.tar.gz\"")
    @test_throws ErrorException render_url(bad; version=v"1.0.0")
end

@testset "update_recipe: archive" begin
    recipe = parse_recipe(joinpath(FIXTURES, "Z", "Zstd", "build_tarballs.jl"))
    fetched = String[]
    fake_hash = url -> (push!(fetched, url); "f"^64)
    text = update_recipe(recipe, v"1.5.7"; archive_hash=fake_hash)

    @test occursin("version = v\"1.5.7\"", text)
    @test !occursin("v\"1.5.6\"", text)
    @test occursin("\"$("f"^64)\"", text)
    @test !occursin(recipe.sources[1].hash, text)
    @test fetched == ["https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz"]
    # Everything else is untouched — same number of lines, script intact
    @test occursin("cd \$WORKSPACE/srcdir/zstd-*/", text)
    @test count(==('\n'), text) == count(==('\n'), recipe.text)

    # The updated text reparses to the new version
    updated = Urdarbrunnr.parse_recipe_text(text)
    @test updated.version == v"1.5.7"

    # Refuses downgrades and no-ops
    @test_throws ErrorException update_recipe(recipe, v"1.5.6"; archive_hash=fake_hash)
    @test_throws ErrorException update_recipe(recipe, v"1.5.5"; archive_hash=fake_hash)
end

@testset "update_recipe: git + static file source" begin
    recipe = parse_recipe(joinpath(FIXTURES, "L", "LibGit", "build_tarballs.jl"))
    resolved = []
    fake_commit = (url, v) -> (push!(resolved, (url, v)); "e"^40)
    fake_hash = url -> error("static FileSource URL should not be re-fetched")
    text = update_recipe(recipe, v"2.4.0"; archive_hash=fake_hash, git_commit=fake_commit)

    @test occursin("version = v\"2.4.0\"", text)
    @test occursin("\"$("e"^40)\"", text)
    @test !occursin("0123456789abcdef0123456789abcdef01234567", text)
    # Static FileSource hash untouched
    @test occursin("aaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999", text)
    @test resolved == [("https://github.com/example/libgit.git", v"2.4.0")]
end

@testset "find_recipe" begin
    @test find_recipe(FIXTURES, "Zstd") == joinpath(FIXTURES, "Z", "Zstd", "build_tarballs.jl")
    @test find_recipe(FIXTURES, "zstd") == joinpath(FIXTURES, "Z", "Zstd", "build_tarballs.jl")
    @test_throws ErrorException find_recipe(FIXTURES, "NoSuchProject")
end

end
