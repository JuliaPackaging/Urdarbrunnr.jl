"""
    archive_sha256(url::AbstractString) -> String

Download `url` to a temporary file and return its SHA256 hex digest.
"""
function archive_sha256(url::AbstractString)
    mktempdir() do dir
        path = joinpath(dir, "download")
        Downloads.download(url, path)
        return bytes2hex(open(sha256, path))
    end
end

"""
    resolve_git_tag(url, current_commit, current_version, new_version) -> String

Find the commit SHA for `new_version`'s tag in the remote repository at
`url`, by learning the tag naming scheme from the recipe's *current* state
rather than guessing: find the tag that points at `current_commit`, locate
`current_version` within that tag name, and substitute `new_version` in its
place. The derived tag must actually exist on the remote — its commit is
returned.

This handles arbitrary prefixes/suffixes (`v1.2.3`, `release-1.2.3`,
`foo_1_2_3`) because everything around the version is preserved verbatim.
"""
function resolve_git_tag(url::AbstractString, current_commit::AbstractString,
                         current_version::VersionNumber, new_version::VersionNumber)
    tags = list_remote_tags(url)
    return derive_tag_commit(tags, current_commit, current_version, new_version; repo=url)
end

"""
    list_remote_tags(url) -> Vector{@NamedTuple{tag::String, commit::String}}

All tags in the remote repository at `url`, each mapped to the commit it
points at (using the peeled `^{}` commit for annotated tags).
"""
list_remote_tags(url::AbstractString) =
    parse_ls_remote(readchomp(`git ls-remote --tags $url`))

"Parse `git ls-remote --tags` output into (tag, commit) pairs."
function parse_ls_remote(out::AbstractString)
    plain = Dict{String,String}()
    peeled = Dict{String,String}()
    for line in eachline(IOBuffer(String(out)))
        isempty(line) && continue
        sha, ref = split(line, '\t'; limit=2)
        startswith(ref, "refs/tags/") || continue
        name = String(@view ref[sizeof("refs/tags/")+1:end])
        if endswith(name, "^{}")
            peeled[chopsuffix(name, "^{}")] = sha
        else
            plain[name] = sha
        end
    end
    return [(tag=t, commit=get(peeled, t, plain[t])) for t in sort!(collect(keys(plain)))]
end

"""
    derive_tag_commit(tags, current_commit, current_version, new_version; repo) -> String

The pure core of [`resolve_git_tag`](@ref): given the remote's (tag, commit)
pairs, derive the new version's tag from the current one and return its
commit. Throws a descriptive error when the scheme can't be inferred or the
new tag doesn't exist (yet).
"""
function derive_tag_commit(tags::Vector, current_commit::AbstractString,
                           current_version::VersionNumber, new_version::VersionNumber;
                           repo::AbstractString="the repository")
    commit_by_tag = Dict(t.tag => t.commit for t in tags)
    current_tags = [t.tag for t in tags if t.commit == current_commit]
    isempty(current_tags) &&
        error("no tag in $repo points at the recipe's current commit $current_commit; " *
              "cannot infer the tag naming scheme")

    tried = String[]
    for tag in current_tags, cur in version_strings(current_version)
        occursin(cur, tag) || continue
        for new in version_strings(new_version)
            candidate = replace(tag, cur => new)
            candidate == tag && continue
            haskey(commit_by_tag, candidate) && return commit_by_tag[candidate]
            push!(tried, candidate)
        end
    end

    isempty(tried) &&
        error("the tag(s) pointing at the current commit ($(join(current_tags, ", "))) " *
              "do not contain the current version $current_version; " *
              "cannot infer the tag naming scheme for $repo")
    error("no tag for version $new_version found in $repo; " *
          "tried: $(join(unique(tried), ", ")) " *
          "(derived from $(join(current_tags, ", ")))")
end

"""
    version_strings(v::VersionNumber) -> Vector{String}

Plausible textual renderings of `v` as found in tag names, most specific
first: `major.minor.patch` (and `major.minor` when the patch is zero), each
with `.`, `_`, and `-` separators.
"""
function version_strings(v::VersionNumber)
    strs = ["$(v.major).$(v.minor).$(v.patch)"]
    v.patch == 0 && push!(strs, "$(v.major).$(v.minor)")
    return unique!([replace(s, "." => sep) for s in strs for sep in (".", "_", "-")])
end
