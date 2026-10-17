using Documenter
using GroundTruth

docs_dir = @__DIR__
build_dir = joinpath(docs_dir, "build")

makedocs(
    root=docs_dir,
    modules=[GroundTruth],
    sitename="GroundTruth.jl",
    authors="Shinichi Nakagawa",
    repo=Documenter.Remotes.GitHub("itchyshin", "GroundTruth.jl"),
    source="src",
    build="build",
    format=Documenter.HTML(
        prettyurls=false,
        edit_link="main",
        repolink="https://github.com/itchyshin/GroundTruth.jl",
        assets=["assets/groundtruth.css"],
    ),
    pages=[
        "Home" => "index.md",
        "Quickstart" => "quickstart.md",
        "Gaussian random intercept" => "random-intercept.md",
        "Random-intercept inference" => "random-intercept-inference.md",
        "Random-intercept reliability" => "random-intercept-reliability.md",
        "Capabilities" => "capabilities.md",
        "Validation" => "validation.md",
        "Roadmap" => "roadmap.md",
    ],
)

# The local preview does not have deployment metadata; avoid missing script requests.
write(joinpath(build_dir, "siteinfo.js"), "// Unversioned documentation site.\n")
write(joinpath(build_dir, "versions.js"), "// No tagged documentation releases yet.\n")
if get(ENV, "GITHUB_ACTIONS", "") != "true"
    for (dir, _, files) in walkdir(build_dir), file in files
        endswith(file, ".html") || continue
        path=joinpath(dir,file)
        relative=relpath(joinpath(build_dir,"versions.js"),dir)
        html=read(path,String)
        write(path,replace(html,r"src=\"(?:\.\./)+versions\.js\""=>"src=\"$relative\""))
    end
end


if get(ENV, "GITHUB_ACTIONS", "") == "true"
    deploydocs(
        repo="github.com/itchyshin/GroundTruth.jl.git",
        devbranch="main",
        versions=nothing,
    )
end

println("DOCUMENTATION_BUILD_OK")
