#!/usr/bin/env julia
# Usage: julia --project bin/update.jl <RecipeName> <new-version> [--dry-run] [--context=<ref>]
#
# Example:
#   julia --project bin/update.jl Zstd 1.5.7 --dry-run
#   julia --project bin/update.jl Zstd 1.5.7 --context=https://github.com/JuliaLang/SecurityAdvisories/pull/123

using Urdarbrunnr

function main(args)
    dry_run = false
    context = nothing
    positional = String[]
    for arg in args
        if arg == "--dry-run"
            dry_run = true
        elseif startswith(arg, "--context=")
            context = chopprefix(arg, "--context=")
        else
            push!(positional, arg)
        end
    end
    if length(positional) != 2
        println(stderr, "usage: update.jl <RecipeName> <new-version> [--dry-run] [--context=<ref>]")
        return 1
    end
    name, version = positional
    create_update_pr(name, VersionNumber(version); dry_run, context)
    return 0
end

exit(main(ARGS))
