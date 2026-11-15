import Foundation

/// Tocador de torrent embutido: toca fonte de addon que só tem `infoHash`, sem
/// depender de Debrid (como o Stremio faz).
///
/// O motor é o `saimo-torrent` (Rust, librqbit), que vai dentro do app em
/// Contents/MacOS. Ele abre um servidor só em 127.0.0.1 e o player toca
/// `http://127.0.0.1:<porta>/tocar?m=<magnet>&f=<arquivo>` como um link comum:
/// baixa primeiro o trecho que o player pede (inclusive ao avançar) e o resto
/// depois. O cache fica em ~/Library/Caches e é apagado quando o filme fecha e
/// quando o app sai (o motor sai junto quando a entrada dele fecha).
@MainActor
final class MotorTorrent {
    static let shared = MotorTorrent()

    private var processo: Process?
    private var entrada: Pipe?
    private var porta: Int = 0

    private var binario: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/saimo-torrent")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    var disponivel: Bool { binario != nil }

    private func iniciar() async throws -> Int {
        if let p = processo, p.isRunning, porta > 0 { return porta }
        guard let bin = binario else { throw DebridErro.respostaInvalida("Torrent", "Motor de torrent ausente.") }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV/torrent")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = bin
        p.arguments = ["--pasta", cache.path, "--porta", "0", "--limite-mb", "8192"]
        let saida = Pipe()
        let entrada = Pipe()
        p.standardOutput = saida
        p.standardError = FileHandle.nullDevice
        p.standardInput = entrada
        try p.run()

        // Primeira linha: "PRONTO <porta>".
        let lida: Int? = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var buffer = Data()
                let fim = Date().addingTimeInterval(15)
                while Date() < fim {
                    let d = saida.fileHandleForReading.availableData
                    if d.isEmpty { break }
                    buffer.append(d)
                    if let texto = String(data: buffer, encoding: .utf8), let linha = texto.split(separator: "\n").first,
                       linha.hasPrefix("PRONTO ") {
                        cont.resume(returning: Int(linha.dropFirst(7).trimmingCharacters(in: .whitespaces)))
                        return
                    }
                }
                cont.resume(returning: nil)
            }
        }
        guard let lida else {
            p.terminate()
            throw DebridErro.respostaInvalida("Torrent", "O motor de torrent não iniciou.")
        }
        processo = p
        self.entrada = entrada
        porta = lida
        return lida
    }

    /// Endereço local para o player tocar o torrent.
    func endereco(infoHash: String, fileIdx: Int?, magnet: String) async throws -> URL {
        let p = try await iniciar()
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = p
        c.path = "/tocar"
        var q = [URLQueryItem(name: "m", value: magnet)]
        if let f = fileIdx, f >= 0 { q.append(URLQueryItem(name: "f", value: String(f))) }
        c.queryItems = q
        // URLComponents não escapa "&" e "=" dentro do valor: o magnet tem os dois.
        c.percentEncodedQuery = q.map { item in
            let v = item.value?.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return "\(item.name)=\(v)"
        }.joined(separator: "&")
        guard let url = c.url else { throw DebridErro.respostaInvalida("Torrent", "Endereço inválido.") }
        return url
    }

    /// O filme fechou: apaga o que baixou. O motor continua no ar.
    func limpar() {
        guard porta > 0, processo?.isRunning == true,
              let url = URL(string: "http://127.0.0.1:\(porta)/parar") else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    nonisolated static func ehEnderecoDoMotor(_ url: URL?) -> Bool {
        url?.host == "127.0.0.1" && url?.path == "/tocar"
    }
}
