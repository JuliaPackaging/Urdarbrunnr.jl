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
    resolve_git_tag(url::AbstractString, version::VersionNumber) -> String

Find the commit SHA for the tag corresponding to `version` in the remote
repository at `url`, trying the common tag spellings (`v1.2.3`, `1.2.3`).
Prefers the peeled (`^{}`) commit of annotated tags over the tag object.
"""
function resolve_git_tag(url::AbstractString, version::VersionNumber)
    for tag in ("v$version", "$version")
        refs = [tag, "$tag^{}"]
        out = readchomp(`git ls-remote --tags $url $refs`)
        isempty(out) && continue
        peeled = nothing
        plain = nothing
        for line in eachline(IOBuffer(out))
            sha, ref = split(line, '\t')
            if endswith(ref, "^{}")
                peeled = sha
            else
                plain = sha
            end
        end
        commit = something(peeled, plain)
        commit === nothing || return String(commit)
    end
    error("no tag matching v$version (or $version) found in $url")
end
