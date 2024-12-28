module Utils

export parse_uri, ParsedURL

"""
    ParsedURL

A structure that holds the parsed components of a URL.

# Fields
- `uri::String`      — The original URL string.
- `scheme::String`   — The URL scheme (e.g., "ws", "wss") or arbitrary string if there's no "://".
- `userinfo::String` — Optional userinfo (e.g., "user:pass") if present.
- `host::String`     — The hostname (e.g., "example.com").
- `port::Union{Int,Nothing}` — The port number, or `nothing` if not specified.
- `path::String`     — The full path (including the leading slash if any).
- `query::String`    — The substring after `?` and before `#`.
- `fragment::String` — The substring after `#`.
"""
struct ParsedURL
    uri::String
    scheme::String
    userinfo::String
    host::String
    port::Union{Int,Nothing}
    path::String
    query::String
    fragment::String
end

"""
    parse_uri(url::String) -> ParsedURL

Parses a URL string into its components and returns a `ParsedURL` structure.

## Arguments
- `url::String`: The URL string to parse.

## Returns
A `ParsedURL` object with the following fields:
- `uri`: the original URL
- `scheme`: the extracted scheme (if `://` is present) or part before the first colon if not
- `userinfo`: user info (e.g., "user:pass") if present
- `host`: the hostname (if `://` is present), otherwise empty
- `port`: the port number if specified; otherwise `nothing`
- `path`: the path including `?` and `#`
- `query`: text after the first `?` and before `#`
- `fragment`: text after the first `#`

## Possible errors
- `ArgumentError` if:
  - the port is invalid (contains non-digits)
"""
function parse_uri(url::String)
    if isempty(url)
        return ParsedURL(url, "", "", "", nothing, "/", "", "")
    end

    port::Union{Int,Nothing} = nothing

    if occursin("://", url)
        scheme, rest = split(url, "://"; limit = 2)
        userinfo = ""

        host_and_port = ""
        remainder = ""

        if occursin('/', rest)
            host_and_port, remainder = split(rest, "/"; limit = 2)
        else
            host_and_port = rest
            remainder = ""
        end

        host = ""

        if !isempty(host_and_port)
            if occursin(':', host_and_port)
                host_part, port_str = split(host_and_port, ":"; limit = 2)
                host = host_part
                if !occursin(r"^[0-9]+$", port_str)
                    throw(ArgumentError("URL parse failed: invalid port '$port_str'"))
                end
                port = parse(Int, port_str)
            else
                host = host_and_port
            end
        end

        path = isempty(remainder) ? "/" : "/" * remainder

        query = ""
        fragment = ""
        qpos = findfirst('?', path)
        fpos = findfirst('#', path)

        if qpos !== nothing
            start_query = qpos + 1
            if fpos !== nothing
                query = path[start_query:fpos-1]
            else
                query = path[start_query:end]
            end
        end

        if fpos !== nothing
            fragment = path[fpos+1:end]
        end

        return ParsedURL(url, scheme, userinfo, host, port, path, query, fragment)

    else
        userinfo = ""
        host = ""
        path = "/"

        colpos = findfirst(':', url)

        if colpos === nothing
            scheme = url
        else
            scheme = url[1:colpos-1]
            rest2 = url[colpos+1:end]

            slashpos = findfirst('/', rest2)
            if slashpos === nothing
                port_str = rest2
                if !isempty(port_str)
                    if !occursin(r"^[0-9]+$", port_str)
                        throw(ArgumentError("URL parse failed: invalid port '$port_str'"))
                    end
                    port = parse(Int, port_str)
                end
            else
                port_str = rest2[1:slashpos-1]
                if !isempty(port_str)
                    if !occursin(r"^[0-9]+$", port_str)
                        throw(ArgumentError("URL parse failed: invalid port '$port_str'"))
                    end
                    port = parse(Int, port_str)
                end
                remainder = rest2[slashpos+1:end]
                path = "/" * remainder
            end
        end

        query = ""
        fragment = ""
        qpos = findfirst('?', path)
        fpos = findfirst('#', path)

        if qpos !== nothing
            start_query = qpos + 1
            if fpos !== nothing
                query = path[start_query:fpos-1]
            else
                query = path[start_query:end]
            end
        end

        if fpos !== nothing
            fragment = path[fpos+1:end]
        end

        return ParsedURL(url, scheme, userinfo, host, port, path, query, fragment)
    end
end

end
