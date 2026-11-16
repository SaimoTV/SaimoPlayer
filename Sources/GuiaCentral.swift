import Foundation

/// Guia de programação já montado no servidor (epg.json do endereço dos canais,
/// gerado às 11h e às 18h). Um arquivo só no lugar de uma página do guiadetv ou
/// do meuguia por canal.
///
/// Chaves iguais às do guia.txt: `g` = slug do guiadetv, `m` = código do
/// meuguia. Cada programa: `[inicio, fim, título, extra]` em segundos (extra =
/// sinopse no `g`, gênero no `m`).
enum GuiaCentral {
    struct Dados: Sendable {
        let guiadetv: [String: [Programme]]
        let meuguia: [String: [Programme]]
    }

    /// nil quando o endereço não publica o arquivo: o app baixa página por página.
    static func carregar(from: Date, to: Date) async -> Dados? {
        guard Enderecos.canaisAtivos, let url = URL(string: Enderecos.canais + "epg.json") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let raiz = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let g = raiz["g"] as? [String: [[Any]]],
              let m = raiz["m"] as? [String: [[Any]]] else { return nil }
        return Dados(guiadetv: grade(g, from: from, to: to, sinopse: true),
                     meuguia: grade(m, from: from, to: to, sinopse: false))
    }

    private static func grade(_ bruto: [String: [[Any]]], from: Date, to: Date, sinopse: Bool) -> [String: [Programme]] {
        var saida: [String: [Programme]] = [:]
        for (chave, lista) in bruto {
            var programas: [Programme] = []
            for p in lista where p.count >= 3 {
                guard let ini = (p[0] as? NSNumber)?.doubleValue, let fim = (p[1] as? NSNumber)?.doubleValue,
                      let titulo = p[2] as? String else { continue }
                let inicio = Date(timeIntervalSince1970: ini)
                let parada = Date(timeIntervalSince1970: fim)
                guard parada > from, inicio < to else { continue }
                let extra = p.count > 3 ? (p[3] as? String ?? "") : ""
                programas.append(Programme(title: titulo, desc: sinopse ? extra : "", category: sinopse ? "" : extra,
                                           start: inicio, stop: parada))
            }
            if !programas.isEmpty { saida[chave] = programas }
        }
        return saida
    }
}
