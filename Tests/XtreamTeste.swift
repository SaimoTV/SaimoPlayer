import Foundation

// Lista com usuário e senha (Xtream): reconhecer o link, normalizar o servidor, ler a API. Sem rede.
// Rodar: ./scripts/testar_xtream.sh
nonisolated(unsafe) var falhas = 0
func conferir(_ ok: Bool, _ nome: String) {
    if !ok { falhas += 1; print("FALHOU: \(nome)") } else { print("ok: \(nome)") }
}
func n(_ s: String) -> String? { Xtream.normalizarServidor(s) }
conferir(n("exemplo.dev:8080") == "http://exemplo.dev:8080", "sem esquema")
conferir(n("  http://exemplo.dev:8080/  ") == "http://exemplo.dev:8080", "trim e barra")
conferir(n("http://exemplo.dev:8080/get.php") == "http://exemplo.dev:8080", "tira get.php")
conferir(n("HTTPS://EXEMPLO.dev/player_api.php") == "https://exemplo.dev", "caixa e player_api")
conferir(n("http://exemplo.dev/painel/") == "http://exemplo.dev/painel", "caminho do painel")
conferir(n("10.0.2.2:8765") == "http://10.0.2.2:8765", "ip com porta")
for ruim in ["", "   ", "ftp://x.dev", "http://", "a b.dev", "http://x.dev:abc", "http://u@x.dev", "http://:80"] {
    conferir(n(ruim) == nil, "recusa '\(ruim)'")
}
let c = Xtream.deLink("http://exemplo.dev:8080/get.php?username=ana&password=s%40nha&type=m3u_plus&output=ts")
conferir(c == Xtream.Conta(base: "http://exemplo.dev:8080", usuario: "ana", senha: "s@nha"), "reconhece a conta")
conferir(c?.canal("12", "m3u8") == "http://exemplo.dev:8080/live/ana/s%40nha/12.m3u8", "url do canal")
conferir(c?.filme("7", "mp4") == "http://exemplo.dev:8080/movie/ana/s%40nha/7.mp4", "url do filme")
conferir(c?.episodio("9", "mkv") == "http://exemplo.dev:8080/series/ana/s%40nha/9.mkv", "url do episodio")
conferir(c.flatMap { Xtream.deLink($0.linkM3u) } == c, "o link montado volta a ser a conta")
conferir(Xtream.deLink("https://exemplo.dev/lista.m3u") == nil, "link comum nao e conta")
conferir(Xtream.deLink("https://exemplo.dev/get.php?username=ana") == nil, "sem senha")
conferir(Xtream.deLink("lixo") == nil, "lixo")
func v(_ s: String) -> String { Xtream.verificarEntrada(Data(s.utf8)) }
conferir(v(#"{"user_info":{"auth":1,"status":"Active","exp_date":"4102444800"}}"#) == "", "conta valida")
conferir(v(#"{"user_info":{"auth":"1","status":"Active","exp_date":null}}"#) == "", "auth texto e sem validade")
conferir(v(#"{"user_info":{"auth":0}}"#) == "Usuário ou senha incorretos", "senha errada")
conferir(v(#"{"user_info":{"auth":1,"status":"Expired"}}"#).contains("não está ativa"), "inativa")
conferir(v(#"{"user_info":{"auth":1,"status":"Active","exp_date":"1000"}}"#) == "Essa conta venceu", "vencida")
conferir(v("<html>painel</html>") == Xtream.semApi && v(#"{"outra":"coisa"}"#) == Xtream.semApi, "sem api")
let conta = Xtream.Conta(base: "http://s.dev:80", usuario: "u", senha: "p")
let cats = Data(#"[{"category_id":"1","category_name":"Abertos"},{"category_id":"3","category_name":"Adultos +18"}]"#.utf8)
let streams = Data(#"""
[{"stream_id":10,"name":"Globo","stream_icon":"http://img/globo.png","category_id":"1"},
 {"stream_id":11,"name":"Globo","stream_icon":"","category_id":"1"},
 {"stream_id":12,"name":"Canal XXX","stream_icon":"","category_id":"3"},
 {"stream_id":13,"name":"Sem categoria","category_id":"99"},
 {"name":"Sem id"}]
"""#.utf8)
let canais = Xtream.canaisDaApi(conta, streams: streams, categorias: cats)
conferir(canais.map(\.nome) == ["Globo", "Canal XXX", "Sem categoria"], "nomes e repetido")
conferir(canais.first?.grupo == "Abertos" && canais.first?.logo == "http://img/globo.png", "grupo e logo")
conferir(canais.first?.fontes == ["http://s.dev:80/live/u/p/10.m3u8", "http://s.dev:80/live/u/p/10.ts",
                                  "http://s.dev:80/live/u/p/11.m3u8", "http://s.dev:80/live/u/p/11.ts"], "duas fontes por canal")
conferir(canais.last?.grupo == nil, "sem categoria")
conferir(Xtream.canaisDaApi(conta, streams: Data("lixo".utf8), categorias: cats).isEmpty, "lixo")
let m3u = Xtream.comoM3u(canais)
conferir(m3u.hasPrefix("#EXTM3U") && m3u.contains("group-title=\"Abertos\",Globo"), "vira m3u")
if case .success(let l) = Xtream.linkDoFormulario("10.0.2.2:8765", usuario: "teste", senha: "senha123") {
    conferir(l == "http://10.0.2.2:8765/get.php?username=teste&password=senha123&type=m3u_plus&output=ts", "formulario com usuario e senha")
} else { conferir(false, "formulario com usuario e senha") }
if case .success(let l) = Xtream.linkDoFormulario(" https://x.dev/lista.m3u ", usuario: "", senha: "") {
    conferir(l == "https://x.dev/lista.m3u", "formulario so com link")
} else { conferir(false, "formulario so com link") }
if case .failure = Xtream.linkDoFormulario("x.dev", usuario: "ana", senha: "") { conferir(true, "usuario sem senha") } else { conferir(false, "usuario sem senha") }
exit(falhas == 0 ? 0 : 1)
