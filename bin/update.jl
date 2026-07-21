#!/usr/bin/env julia
# Usage: julia --project bin/update.jl <RecipeName> <new-version> [--dry-run]
#
# Example:
#   julia --project bin/update.jl Zstd 1.5.7 --dry-run

using Urdarbrunnr

function main(args)
    dry_run = "--dry-run" in args
    args = filter(!=("--dry-run"), args)
    if length(args) != 2
        println(stderr, "usage: update.jl <RecipeName> <new-version> [--dry-run]")
        return 1
    end
    name, version = args
    create_update_pr(name, VersionNumber(version); dry_run)
    return 0
end

exit(main(ARGS))
