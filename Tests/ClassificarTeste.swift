import Foundation

// Confere Sources/Classificar.swift contra o gabarito comum (docs/exemplos/listas).
func atributo(_ linha: String, _ nome: String) -> String {
    guard let r = linha.range(of: "\(nome)=\"") else { return "" }
    return String(linha[r.upperBound...].prefix { $0 != "\"" }).trimmingCharacters(in: .whitespaces)
}

let texto = try! String(contentsOfFile: "docs/exemplos/listas/classificar.m3u", encoding: .utf8)
let esperado = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "docs/exemplos/listas/classificar.esperado.json"))) as! [[String: Any]]
var pend = ""
var i = 0
var falhas = 0
for linha in texto.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
    if linha.hasPrefix("#EXTINF") { pend = linha; continue }
    if linha.isEmpty || linha.hasPrefix("#") { continue }
    let nome = pend.range(of: "\",", options: .backwards).map { String(pend[$0.upperBound...]) }
        ?? pend.range(of: ",").map { String(pend[$0.upperBound...]) } ?? ""
    let n = nome.trimmingCharacters(in: .whitespaces)
    let grupo = atributo(pend, "group-title")
    let declarado = [atributo(pend, "tvg-type"), atributo(pend, "type")].first { !$0.isEmpty } ?? ""
    var obtido: [String: String] = ["nome": n]
    switch Classificar.tipo(url: linha, nome: n, grupo: grupo, declarado: declarado) {
    case .canal: obtido["tipo"] = "canal"
    case .filme:
        let t = Classificar.tituloDoFilme(n, grupo: grupo)
        obtido = obtido.merging(["tipo": "filme", "titulo": t.titulo, "ano": t.ano, "versao": t.versao]) { $1 }
    case .episodio(let m):
        let t = Classificar.tituloDaSerie(n, inicio: m.inicio, grupo: grupo)
        obtido = obtido.merging(["tipo": "episodio", "titulo": t.titulo, "ano": t.ano, "versao": t.versao,
                                 "temporada": "\(m.temporada)", "episodio": "\(m.episodio)"]) { $1 }
    }
    let e = esperado[i].mapValues { "\($0)" }
    if e != obtido { print("ERRO item \(i): esperado \(e) obtido \(obtido)"); falhas += 1 } else { print("ok \(i)") }
    i += 1
}
if i != esperado.count { print("ERRO: \(i) itens, esperado \(esperado.count)"); falhas += 1 }
exit(falhas == 0 ? 0 : 1)
