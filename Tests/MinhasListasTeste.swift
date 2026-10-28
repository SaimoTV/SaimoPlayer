// Teste do leitor de .m3u contra o gabarito (edge e br) + casos de lixo.
// Rodar: ./scripts/testar_minhas_listas.sh [pasta com edge.m3u, edge.golden.json, br.m3u, br.golden.json]
import Foundation

var falhas = 0
@MainActor func conferir(_ ok: Bool, _ msg: String) {
    if ok { print("ok  \(msg)") } else { print("FALHOU  \(msg)"); falhas += 1 }
}

func comoJSON(_ canais: [CanalLido]) -> [[String: Any]] {
    func v(_ s: String?) -> Any { s ?? NSNull() }
    return canais.map { c in
        ["nome": c.nome, "grupo": v(c.grupo), "logo": v(c.logo),
         "fontes": c.fontes.map { f in
            ["url": f.url, "referer": v(f.referer), "ua": v(f.ua), "keyId": v(f.keyId),
             "key": v(f.key), "qualidade": v(f.qualidade)] as [String: Any]
         }] as [String: Any]
    }
}

let pasta = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for nome in ["edge", "br"] {
    let m3u = "\(pasta)/\(nome).m3u", ouro = "\(pasta)/\(nome).golden.json"
    guard let dados = FileManager.default.contents(atPath: m3u),
          let json = FileManager.default.contents(atPath: ouro),
          let esperado = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
        print("FALHOU  nao achei \(nome).m3u/golden em \(pasta)"); falhas += 1; continue
    }
    let lidos = LeitorM3u.ler(String(decoding: dados, as: UTF8.self))
    let obtido = comoJSON(lidos)
    conferir(obtido.count == esperado.count, "\(nome): \(obtido.count) canais (esperado \(esperado.count))")
    var diverge = 0
    for (i, e) in esperado.enumerated() where i < obtido.count {
        if !(obtido[i] as NSDictionary).isEqual(to: e) {
            diverge += 1
            if diverge <= 3 { print("  difere no canal \(i): \(obtido[i]) != \(e)") }
        }
    }
    conferir(diverge == 0, "\(nome): todos os campos iguais ao gabarito")
    if nome == "br" {
        conferir(lidos.reduce(0) { $0 + $1.fontes.count } == 398, "br: 398 fontes")
        conferir(lidos.filter { $0.logo != nil }.count == 393, "br: 393 com logo")
        conferir(lidos.filter { $0.grupo != nil }.count == 398, "br: 398 com grupo")
    }
}

// Lixo, vazio e linhas enormes: nunca falha, devolve vazio.
var binario = [UInt8](); for i in 0..<20000 { binario.append(UInt8((i * 7919 + 13) % 256)) }
conferir(LeitorM3u.ler(String(decoding: binario, as: UTF8.self)).isEmpty, "lixo binario -> vazio")
conferir(LeitorM3u.ler("").isEmpty, "arquivo vazio -> vazio")
conferir(LeitorM3u.ler("\u{FEFF}\r\n\r\n").isEmpty, "so BOM e quebras -> vazio")
let enorme = "#EXTM3U\n#EXTINF:-1," + String(repeating: "x", count: 1_000_000) + "\nhttp://a/b\n" + String(repeating: "(", count: 1_000_000)
let r = LeitorM3u.ler(enorme)
conferir(r.count == 1, "linha de 1 MB nao quebra")
conferir(LeitorM3u.ler("<html><body>oi</body></html>").isEmpty, "pagina HTML -> vazio")
conferir(!LeitorM3u.pareceLista("<html><body>oi</body></html>"), "HTML nao parece lista")
conferir(LeitorM3u.pareceLista("\u{FEFF}  \n#extm3u\n"), "cabecalho com BOM parece lista")
conferir(LeitorM3u.pareceLista("x\n#EXTINF:-1,A\nhttp://a\n"), "EXTINF sem cabecalho parece lista")
conferir(LeitorM3u.ler("rtmp://x/y\nudp://@1.2.3.4:1\n").isEmpty, "so rtmp/udp -> vazio")

// Conteudo adulto
conferir(LeitorM3u.ehRestrito(nome: "Canal X", grupo: "Adult"), "grupo Adult e restrito")
conferir(LeitorM3u.ehRestrito(nome: "Playboy XXX", grupo: nil), "xxx e restrito")
conferir(LeitorM3u.ehRestrito(nome: "Canal", grupo: "Erótico"), "acento: Erótico e restrito")
conferir(!LeitorM3u.ehRestrito(nome: "Adult Swim", grupo: "Desenhos"), "Adult Swim nao e restrito")
conferir(!LeitorM3u.ehRestrito(nome: "Adult Swim Brasil", grupo: nil), "Adult Swim Brasil nao e restrito")
conferir(!LeitorM3u.ehRestrito(nome: "Sexta Maluca", grupo: "Filmes"), "Sexta nao e restrito")
conferir(LeitorM3u.ehRestrito(nome: "Hot 18+", grupo: nil), "18+ e restrito")

if falhas > 0 { print("\(falhas) falha(s)"); exit(1) }
print("minhas listas: tudo certo")
