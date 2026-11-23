import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct TelaAddonsView: View {
    var aoFechar: (() -> Void)? = nil

    @ObservedObject private var store = AddonStore.shared
    @ObservedObject private var debrid = DebridStore.shared

    @State private var urlInput = ""
    @State private var instalando = false
    @State private var erroInstalacao: String?
    @State private var avisoSucesso: String?
    @State private var expandidoId: UUID?
    @State private var chavesEditando: [DebridProvedor: String] = [:]
    @State private var chaveVisivel: Set<DebridProvedor> = []
    @State private var qrImage: NSImage?
    @State private var copiadoURL = false

    private var enderecoWebAddons: String {
        let host = ProxyServer.lanAddress() ?? "127.0.0.1"
        return "http://\(host):8999/addons"
    }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 0) {
                cabecalho
                Divider().overlay(Color.white.opacity(0.08))

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        blocoQRRemoto
                        blocoInstalarAddon
                        blocoListaAddons
                        blocoDebrid
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 740, minHeight: 620)
        .onAppear {
            sincronizarCamposDebrid()
            qrImage = Self.gerarQRCode(para: enderecoWebAddons)
        }
        .onChange(of: debrid.configuracao) { _, _ in
            sincronizarCamposDebrid()
        }
    }

    private var cabecalho: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Addons Stremio e Debrid")
                    .font(.escalado(19, weight: .bold))
                    .foregroundStyle(.white)
                Text("Protocolo HTTP Stremio (/manifest.json) + resolução Debrid no cliente")
                    .font(.escalado(12.5))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if let aoFechar {
                Button("Concluir", action: aoFechar)
                    .buttonStyle(.borderedProminent)
                    .tint(Tema.acento)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - QR Code Remoto (`:8999/addons`)

    private var blocoQRRemoto: some View {
        HStack(spacing: 18) {
            Group {
                if let qrImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(22)
                        .frame(width: 230, height: 230)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                        .frame(width: 112, height: 112)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Configurar pelo celular ou navegador", systemImage: "qrcode")
                    .font(.escalado(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Escaneie o QR Code ou abra este endereço na mesma rede Wi-Fi para colar URLs de addons e chaves Debrid rapidamente:")
                    .font(.escalado(12.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(enderecoWebAddons)
                        .font(.escalado(12.5, design: .monospaced))
                        .foregroundStyle(Tema.acento)
                        .textSelection(.enabled)
                    Button(copiadoURL ? "Copiado!" : "Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(enderecoWebAddons, forType: .string)
                        copiadoURL = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiadoURL = false }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Instalar Addon Stremio

    private var blocoInstalarAddon: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instalar addon Stremio")
                .font(.escalado(15, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                TextField("https://.../manifest.json ou stremio://...", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { instalar() }

                Button {
                    instalar()
                } label: {
                    if instalando {
                        ProgressView().controlSize(.small)
                            .frame(width: 110)
                    } else {
                        Text("Instalar")
                            .frame(width: 110)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tema.acento)
                .disabled(instalando || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let erroInstalacao {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(erroInstalacao)
                        .font(.escalado(12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let avisoSucesso {
                Text(avisoSucesso)
                    .font(.escalado(12))
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Lista de Addons Instalados

    private var blocoListaAddons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Addons instalados (\(store.addons.count))")
                    .font(.escalado(15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            if store.addons.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.escalado(26))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Nenhum addon instalado.")
                        .font(.escalado(13.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("O Saimo começa vazio por padrão. Cole acima a URL /manifest.json de qualquer addon HTTP Stremio que você desejar usar.")
                        .font(.escalado(12))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(store.catalogoPorId()) { item in
                    linhaAddon(item)
                }
            }
        }
    }

    @ViewBuilder
    private func linhaAddon(_ item: AddonInstalado) -> some View {
        let expandido = expandidoId == item.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { item.enabled },
                    set: { store.definirAtivo(id: item.id, ativo: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.manifest.name)
                            .font(.escalado(14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("v\(item.manifest.version)")
                            .font(.escalado(11))
                            .foregroundStyle(.white.opacity(0.5))
                        if item.manifest.behaviorHints?.configurationRequired == true {
                            badge("Requer configuração", cor: .orange)
                        }
                        if item.manifest.behaviorHints?.p2p == true {
                            badge("P2P", cor: .yellow)
                        }
                    }
                    Text(item.manifestUrlString)
                        .font(.escalado(11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button { store.mover(id: item.id, deslocamento: -1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .help("Subir prioridade")

                    Button { store.mover(id: item.id, deslocamento: 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .help("Descer prioridade")

                    Button {
                        expandidoId = expandido ? nil : item.id
                    } label: {
                        Image(systemName: expandido ? "chevron.up" : "info.circle")
                    }
                    .help("Ver recursos e catálogos")

                    if item.manifest.behaviorHints?.configurable == true,
                       let cfg = item.transport.configureUrl {
                        Button { NSWorkspace.shared.open(cfg) } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .help("Abrir página de configuração do addon")
                    }

                    Button {
                        Task { try? await store.recarregar(id: item.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Recarregar manifesto")

                    Button(role: .destructive) {
                        store.remover(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remover addon")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if expandido {
                VStack(alignment: .leading, spacing: 6) {
                    if let desc = item.manifest.description, !desc.isEmpty {
                        Text(desc)
                            .font(.escalado(12))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Text("Recursos: \(item.manifest.resources.map(\.name).joined(separator: ", "))")
                        .font(.escalado(11.5))
                        .foregroundStyle(.white.opacity(0.6))
                    if let prefixos = item.manifest.idPrefixes, !prefixos.isEmpty {
                        Text("Prefixos de ID: \(prefixos.joined(separator: ", "))")
                            .font(.escalado(11.5))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if !item.manifest.catalogs.isEmpty {
                        Text("Catálogos (\(item.manifest.catalogs.count)): " + item.manifest.catalogs.map { "\($0.tituloExibicao) [\($0.type)]" }.joined(separator: " · "))
                            .font(.escalado(11.5))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Serviços Debrid

    private var blocoDebrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Serviços Debrid (TorBox, Real-Debrid, AllDebrid, Premiumize)")
                    .font(.escalado(15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Torrents P2P (infoHash) são convertidos sob demanda em HTTPS direto na sua conta Debrid. O Saimo não executa cliente torrent local.")
                    .font(.escalado(12))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ForEach(DebridProvedor.allCases) { provedor in
                let entrada = debrid.entrada(para: provedor)
                let bindingKey = Binding<String>(
                    get: { chavesEditando[provedor] ?? entrada.apiKey },
                    set: { novo in
                        chavesEditando[provedor] = novo
                        debrid.definir(provedor: provedor, apiKey: novo)
                    }
                )
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { entrada.enabled },
                            set: { debrid.definir(provedor: provedor, enabled: $0) }
                        )) {
                            HStack(spacing: 8) {
                                Text(provedor.nome)
                                    .font(.escalado(13.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(provedor.dicaChave)
                                    .font(.escalado(11))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .toggleStyle(.switch)
                        Spacer()
                        if entrada.ativoValido {
                            badge("Ativo", cor: .green)
                        }
                    }

                    HStack(spacing: 8) {
                        if chaveVisivel.contains(provedor) {
                            TextField("Cole sua API Key de \(provedor.nome)", text: bindingKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Cole sua API Key de \(provedor.nome)", text: bindingKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            if chaveVisivel.contains(provedor) { chaveVisivel.remove(provedor) }
                            else { chaveVisivel.insert(provedor) }
                        } label: {
                            Image(systemName: chaveVisivel.contains(provedor) ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            Toggle(isOn: Binding(
                get: { debrid.sincronizarConnect },
                set: { debrid.definirSincronizarConnect($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sincronizar chaves Debrid via Saimo Connect")
                        .font(.escalado(13, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Desativado por padrão por segurança. Quando ativo, envia suas chaves aos aparelhos pareados na sua rede.")
                        .font(.escalado(11.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Ações & QR Generator

    private func instalar() {
        let bruto = urlInput
        erroInstalacao = nil
        avisoSucesso = nil
        instalando = true
        Task { @MainActor in
            defer { instalando = false }
            do {
                let instalado = try await store.instalar(url: bruto)
                urlInput = ""
                avisoSucesso = "Addon '\(instalado.manifest.name)' instalado com sucesso."
                SaimoConnect.shared.avisarDados(atraso: 2)
            } catch {
                erroInstalacao = error.localizedDescription
            }
        }
    }

    private func sincronizarCamposDebrid() {
        for p in DebridProvedor.allCases {
            let salvo = debrid.entrada(para: p).apiKey
            if chavesEditando[p] == nil || chavesEditando[p] != salvo {
                chavesEditando[p] = salvo
            }
        }
    }

    private func badge(_ texto: String, cor: Color) -> some View {
        Text(texto)
            .font(.escalado(10.5, weight: .semibold))
            .foregroundStyle(cor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(cor.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
    }

    static func gerarQRCode(para texto: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(texto.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
