using Websockets
using Documenter

DocMeta.setdocmeta!(Websockets, :DocTestSetup, :(using Websockets); recursive = true)

makedocs(;
    modules = [Websockets],
    sitename = "Websockets.jl",
    format = Documenter.HTML(;
        repolink = "https://github.com/zaeba1sya/Websockets.jl",
        canonical = "https://zaeba1sya.github.io/Websockets.jl",
        edit_link = "master",
        assets = ["assets/favicon.ico"],
        sidebar_sitename = true,  # Set to 'false' if the package logo already contain its name
    ),
    pages = [
        "Home"    => "index.md",
        "Content" => "pages/content.md",
        # Add your pages here ...
    ],
    warnonly = [:doctest, :missing_docs],
)

deploydocs(;
    repo = "github.com/zaeba1sya/Websockets.jl",
    devbranch = "master",
    push_preview = true,
)
