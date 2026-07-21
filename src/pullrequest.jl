"""
    Config

Settings for talking to Yggdrasil and the bot's fork. Defaults are read
from the environment so the same code works locally and in CI:

- `URDARBRUNNR_FORK`: `owner/repo` slug of the bot's fork (required to open PRs)
- `URDARBRUNNR_CLONE`: where to keep the working clone of Yggdrasil
- `URDARBRUNNR_GIT_NAME` / `URDARBRUNNR_GIT_EMAIL`: commit author identity

Authentication is delegated entirely to `gh`: set `GH_TOKEN` to the bot
account's token (and run `gh auth setup-git`, or rely on `gh` credential
helper) so both pushes and PR creation act as the bot.
"""
Base.@kwdef struct Config
    upstream::String = "JuliaPackaging/Yggdrasil"
    branch::String = "master"
    fork::String = get(ENV, "URDARBRUNNR_FORK", "")
    clone_dir::String = get(ENV, "URDARBRUNNR_CLONE",
                            joinpath(homedir(), ".urdarbrunnr", "Yggdrasil"))
    git_name::String = get(ENV, "URDARBRUNNR_GIT_NAME", "urdarbrunnr[bot]")
    git_email::String = get(ENV, "URDARBRUNNR_GIT_EMAIL", "urdarbrunnr@juliahub.com")
end

git(cfg::Config, args...) = run(`git -C $(cfg.clone_dir) $(collect(args))`)
gitread(cfg::Config, args...) = readchomp(`git -C $(cfg.clone_dir) $(collect(args))`)

"""
    ensure_clone!(cfg::Config) -> String

Make sure a checkout of upstream Yggdrasil exists at `cfg.clone_dir` and is
up to date, and return that path. Uses a blobless partial clone since
Yggdrasil's history is large and we only ever touch one recipe.
"""
function ensure_clone!(cfg::Config)
    if !isdir(joinpath(cfg.clone_dir, ".git"))
        mkpath(dirname(cfg.clone_dir))
        run(`git clone --filter=blob:none https://github.com/$(cfg.upstream).git $(cfg.clone_dir)`)
    else
        git(cfg, "fetch", "origin", cfg.branch)
    end
    return cfg.clone_dir
end

"""
    find_recipe(root::AbstractString, name::AbstractString) -> String

Locate `<root>/<letter>/<Name>/build_tarballs.jl` for a project name,
matching case-insensitively. Throws if the recipe doesn't exist or the
name is ambiguous.
"""
function find_recipe(root::AbstractString, name::AbstractString)
    # Always scan rather than probing an exact path: this both handles
    # case-insensitive matching and returns the on-disk casing of the path
    # even on case-insensitive filesystems.
    matches = String[]
    for shard in readdir(root; join=true)
        isdir(shard) || continue
        startswith(basename(shard), ".") && continue
        for dir in readdir(shard; join=true)
            if lowercase(basename(dir)) == lowercase(name)
                candidate = joinpath(dir, "build_tarballs.jl")
                isfile(candidate) && push!(matches, candidate)
            end
        end
    end
    length(matches) == 1 && return only(matches)
    isempty(matches) && error("no recipe named $name found under $root")
    error("multiple recipes match $name: $(join(matches, ", "))")
end

"""
    create_update_pr(name, new_version; cfg=Config(), dry_run=false) -> Union{String,Nothing}

The full pipeline: update the recipe for `name` to `new_version`, commit it
on a fresh branch, push that branch to the bot's fork, and open a PR
against upstream Yggdrasil. Returns the PR URL.

With `dry_run=true`, stops after applying the update: prints the diff,
restores the working tree, and returns `nothing`.
"""
function create_update_pr(name::AbstractString, new_version::VersionNumber;
                          cfg::Config=Config(), dry_run::Bool=false)
    root = ensure_clone!(cfg)
    branch = "urdarbrunnr/$(lowercase(name))-v$(new_version)"
    git(cfg, "checkout", "--quiet", "-B", branch, "origin/$(cfg.branch)")

    recipe_path = find_recipe(root, name)
    recipe = parse_recipe(recipe_path)
    recipe.version == new_version &&
        error("$(recipe.name) is already at $new_version")

    @info "Updating $(recipe.name): $(recipe.version) → $new_version"
    write(recipe_path, update_recipe(recipe, new_version))

    if dry_run
        run(pipeline(`git -C $root --no-pager diff`, stdout))
        git(cfg, "checkout", "--quiet", "--", ".")
        git(cfg, "checkout", "--quiet", cfg.branch)
        return nothing
    end

    isempty(cfg.fork) &&
        error("no fork configured: set URDARBRUNNR_FORK to the bot's owner/repo slug")

    title = "[$(recipe.name)] Update to v$new_version"
    body = """
    Update $(recipe.name) from v$(recipe.version) to v$new_version.

    This pull request was generated automatically by
    [Urdarbrunnr](https://github.com/JuliaComputing/Urdarbrunnr); source
    hashes were recomputed from the re-rendered source URLs.
    """
    git(cfg, "-c", "user.name=$(cfg.git_name)", "-c", "user.email=$(cfg.git_email)",
        "commit", "--quiet", "--all", "--message", title)
    git(cfg, "push", "--force", "https://github.com/$(cfg.fork).git", "$branch:$branch")

    fork_owner = first(split(cfg.fork, '/'))
    url = readchomp(setenv(`gh pr create --repo $(cfg.upstream) --head $fork_owner:$branch
                            --title $title --body $body`; dir=root))
    @info "Opened $url"
    return url
end
