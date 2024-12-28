include("../src/Utils.jl")

@testset "parse_uri Tests" begin
    # Тест 1: URL без схемы
    r = Utils.parse_uri("example.com:8080/path")
    @test r.uri == "example.com:8080/path"
    @test r.scheme == "example.com"
    @test r.userinfo == ""
    @test r.host == ""
    @test r.port == 8080
    @test r.path == "/path"
    @test r.query == ""
    @test r.fragment == ""

    # Тест 2: Пустая строка
    r = Utils.parse_uri("")
    @test r.uri == ""
    @test r.scheme == ""
    @test r.userinfo == ""
    @test r.host == ""
    @test r.port === nothing
    @test r.path == "/"
    @test r.query == ""
    @test r.fragment == ""

    # Тест 3: URL с пустой схемой
    r = Utils.parse_uri("http://")
    @test r.uri == "http://"
    @test r.scheme == "http"
    @test r.userinfo == ""
    @test r.host == ""
    @test r.port === nothing
    @test r.path == "/"
    @test r.query == ""
    @test r.fragment == ""

    # Тест 4: Некорректный порт
    @test_throws ArgumentError Utils.parse_uri("http://example.com:abc/path")

    # Тест 5: Сложный URL с query и fragment
    r = Utils.parse_uri("http://example.com:8080/path?query=1#fragment")
    @test r.uri == "http://example.com:8080/path?query=1#fragment"
    @test r.scheme == "http"
    @test r.userinfo == ""
    @test r.host == "example.com"
    @test r.port == 8080
    @test r.path == "/path?query=1#fragment"
    @test r.query == "query=1"
    @test r.fragment == "fragment"
end
