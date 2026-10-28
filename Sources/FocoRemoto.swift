import AppKit

/// Foco do controle remoto (Saimo Connect) nas telas de mouse: Início, On
/// Demand, Eventos, Rádios, Busca, Ajustes.
///
/// Essas telas não têm foco de teclado próprio, então em vez de ensinar cada
/// uma a andar com setas, o foco lê o que é clicável na janela pela árvore de
/// acessibilidade do próprio app (botões, links, células — o mesmo que o
/// VoiceOver enxerga, sem pedir permissão nenhuma), anda para o vizinho mais
/// próximo na direção pedida, rola a lista quando acaba o que está à vista e,
/// no OK, aperta o elemento como um clique. Um contorno desenhado numa janela
/// transparente por cima mostra onde está o foco.
@MainActor
final class FocoRemoto {
    static let shared = FocoRemoto()

    enum Direcao { case cima, baixo, esquerda, direita }

    private struct Alvo {
        let elemento: NSObject
        let quadro: NSRect   // coordenadas de tela (origem embaixo à esquerda)
        var centro: NSPoint { NSPoint(x: quadro.midX, y: quadro.midY) }
    }

    private static let papeis: Set<NSAccessibility.Role> = [
        .button, .link, .cell, .checkBox, .radioButton, .popUpButton,
        .menuButton, .disclosureTriangle, .slider, .textField, .image,
    ]

    private weak var atual: NSObject?
    private var quadroAtual: NSRect?
    private var contorno: NSWindow?
    private var apagar: DispatchWorkItem?

    // MARK: - Comandos

    func mover(_ direcao: Direcao) {
        guard let janela = janelaPrincipal() else { return }
        let alvos = coletar(janela)
        guard !alvos.isEmpty else { return }
        guard let origem = alvoAtual(em: alvos) else {
            focar(primeiro(alvos), janela)
            return
        }
        if let proximo = vizinho(de: origem, para: direcao, entre: alvos) {
            focar(proximo, janela)
            return
        }
        // Nada à vista naquela direção: rola a lista e tenta de novo, para
        // descer pelas fileiras que o SwiftUI só desenha quando aparecem.
        guard rolar(origem, direcao) else { mostrar(origem.quadro, janela); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + ((direcao == .cima || direcao == .baixo) ? 0.2 : 0.45)) { [weak self] in
            guard let self, let janela = self.janelaPrincipal() else { return }
            let novos = self.coletar(janela)
            let referencia = self.alvoAtual(em: novos) ?? origem
            if let proximo = self.vizinho(de: referencia, para: direcao, entre: novos) {
                self.focar(proximo, janela)
            } else if let mesmo = self.alvoAtual(em: novos) {
                self.mostrar(mesmo.quadro, janela)
            }
        }
    }

    /// OK do controle: aperta o elemento em foco (ou foca o primeiro, se nada
    /// estava em foco ainda). Devolve false quando não havia o que apertar.
    @discardableResult
    func confirmar() -> Bool {
        guard let janela = janelaPrincipal() else { return false }
        let alvos = coletar(janela)
        guard let alvo = alvoAtual(em: alvos) else {
            guard !alvos.isEmpty else { return false }
            focar(primeiro(alvos), janela)
            return true
        }
        let antes = assinatura(alvos)
        let janelaAntes = janela
        apertar(alvo, janela)
        // O clique costuma abrir algo (diálogo, ficha, outra tela): o foco vai
        // para o primeiro item que apareceu; senão continua onde estava.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let janela = self.janelaPrincipal() else { return }
            let novos = self.coletar(janela)
            let surgiram = novos.filter { !antes.contains(self.assinatura([$0]).first!) }
            if janela !== janelaAntes || surgiram.count >= 2 {
                let base = (janela !== janelaAntes || surgiram.isEmpty) ? novos : surgiram
                if !base.isEmpty { self.focar(self.primeiro(base), janela) } else { self.esquecer() }
            } else if let ainda = self.alvoAtual(em: novos) {
                self.mostrar(ainda.quadro, janela)
            } else {
                self.esquecer()
            }
        }
        return true
    }

    /// Voltar nas telas de mouse: primeiro um Esc (fecha a folha de escolha
    /// de fonte, a ficha, a série — tudo que já fecha com Esc no teclado). Se
    /// nada mudou na tela, aí sim volta de tela com `senao`.
    func voltar(senao: @escaping @MainActor () -> Void) {
        guard let janela = janelaPrincipal() else { senao(); return }
        let antes = assinatura(coletar(janela))
        let tinhaFolha = janela.sheetParent != nil
        for tipo in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: tipo, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: janela.windowNumber, context: nil, characters: "\u{1b}",
                                        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                janela.sendEvent(e)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let agora = self.janelaPrincipal()
            let mudou = tinhaFolha ? agora !== janela : (agora.map { self.assinatura(self.coletar($0)) } ?? []) != antes
            self.esquecer()
            if !mudou { senao() }
        }
    }

    /// Troca de tela pelo Voltar, Início ou Menu: o foco antigo não vale mais.
    func esquecer() {
        atual = nil
        quadroAtual = nil
        contorno?.orderOut(nil)
    }

    // MARK: - Coleta

    private func janelaPrincipal() -> NSWindow? {
        let candidatas = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.windows
        let principal = candidatas.compactMap { $0 }.first {
            $0.isVisible && $0 !== contorno && $0.sheetParent == nil && !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }
        // Diálogo em folha (escolha de fonte, confirmações): o foco fica nele.
        if let folha = principal?.attachedSheet, folha.isVisible { return folha }
        return principal
    }

    /// Assinatura do que está clicável na tela, para saber se algo abriu ou fechou.
    private func assinatura(_ alvos: [Alvo]) -> Set<String> {
        Set(alvos.map { "\(Int($0.quadro.minX / 4)),\(Int($0.quadro.minY / 4)),\(Int($0.quadro.width / 4))" })
    }

    private func coletar(_ janela: NSWindow) -> [Alvo] {
        guard let raiz = janela.contentView else { return [] }
        let visivel = janela.frame
        var saida: [Alvo] = []
        var pilha: [Any] = [raiz]
        var vistos = 0
        while let item = pilha.popLast(), vistos < 6000 {
            vistos += 1
            // Os nós do SwiftUI (AccessibilityNode) respondem aos métodos de
            // acessibilidade mas não passam no cast para o protocolo: chamada
            // dinâmica pelo AnyObject, que serve para os dois.
            guard let no = item as? NSObject else { continue }
            let ax = no as AnyObject
            if let papel = ax.accessibilityRole?(), Self.papeis.contains(papel), ax.isAccessibilityEnabled?() ?? true,
               let quadro = ax.accessibilityFrame?() {
                // Só o que está de fato à vista, com tamanho de algo clicável.
                if quadro.width >= 8, quadro.height >= 8,
                   quadro.width < visivel.width * 0.95 || quadro.height < visivel.height * 0.5,
                   visivel.intersects(quadro),
                   papel != NSAccessibility.Role.image || no.responds(to: #selector(NSAccessibilityProtocol.accessibilityPerformPress)) {
                    saida.append(Alvo(elemento: no, quadro: quadro))
                    continue
                }
            }
            if let filhos = ax.accessibilityChildren?() ?? nil { pilha.append(contentsOf: filhos) }
        }
        return saida
    }

    private func alvoAtual(em alvos: [Alvo]) -> Alvo? {
        if let atual, let mesmo = alvos.first(where: { $0.elemento === atual }) { return mesmo }
        // O SwiftUI recria os nós: acha pelo lugar onde o foco estava.
        guard let quadroAtual else { return nil }
        let c = NSPoint(x: quadroAtual.midX, y: quadroAtual.midY)
        return alvos.min { distancia($0.centro, c) < distancia($1.centro, c) }
            .flatMap { distancia($0.centro, c) < 60 ? $0 : nil }
    }

    /// Começa pelo canto de cima à esquerda do conteúdo, abaixo da barra do topo.
    private func primeiro(_ alvos: [Alvo]) -> Alvo {
        let topo = alvos.map(\.quadro.maxY).max() ?? 0
        // Na janela principal a primeira linha é a barra de abas; num diálogo, não.
        let emDialogo = janelaPrincipal()?.sheetParent != nil
        let conteudo = emDialogo ? alvos : alvos.filter { $0.quadro.maxY < topo - 40 }
        let base = conteudo.isEmpty ? alvos : conteudo
        return base.min { ($0.quadro.maxY > $1.quadro.maxY + 4) || (abs($0.quadro.maxY - $1.quadro.maxY) <= 4 && $0.quadro.minX < $1.quadro.minX) }!
    }

    private func vizinho(de origem: Alvo, para direcao: Direcao, entre alvos: [Alvo]) -> Alvo? {
        let o = origem.centro
        var melhor: (Alvo, CGFloat)?
        for alvo in alvos where alvo.elemento !== origem.elemento {
            let c = alvo.centro
            let dx = c.x - o.x, dy = c.y - o.y   // y cresce para cima
            let principal: CGFloat, lateral: CGFloat
            switch direcao {
            case .cima: principal = dy; lateral = dx
            case .baixo: principal = -dy; lateral = dx
            case .direita: principal = dx; lateral = dy
            case .esquerda: principal = -dx; lateral = dy
            }
            // Precisa estar mesmo naquele lado, não só um pixel ao lado.
            guard principal > 6 else { continue }
            // Distância pelas bordas, não pelo centro: uma linha larga logo
            // acima é vizinha direta de um botão pequeno à direita dela.
            let a = origem.quadro, q = alvo.quadro
            let vaoX = max(0, max(q.minX - a.maxX, a.minX - q.maxX))
            let vaoY = max(0, max(q.minY - a.maxY, a.minY - q.maxY))
            // De lado, só na mesma fileira: sem vizinho ali, a fileira rola.
            if direcao == .esquerda || direcao == .direita {
                let faixa = max(origem.quadro.height, alvo.quadro.height) * 0.5
                guard abs(dy) < faixa else { continue }
            }
            let vaoPrincipal = (direcao == .cima || direcao == .baixo) ? vaoY : vaoX
            let vaoLateral = (direcao == .cima || direcao == .baixo) ? vaoX : vaoY
            let nota = vaoPrincipal + vaoLateral * 3 + abs(lateral) * 0.05 + principal * 0.01
            if melhor == nil || nota < melhor!.1 { melhor = (alvo, nota) }
        }
        return melhor?.0
    }

    // MARK: - Ação

    private func focar(_ alvo: Alvo, _ janela: NSWindow) {
        atual = alvo.elemento
        quadroAtual = alvo.quadro
        trazerParaAVista(alvo)
        // Depois de rolar o quadro muda: relê para desenhar no lugar certo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let quadro = ((self.atual as AnyObject?)?.accessibilityFrame?()).flatMap { $0.isEmpty ? nil : $0 } ?? alvo.quadro
            self.quadroAtual = quadro
            self.mostrar(quadro, janela)
        }
    }

    private func apertar(_ alvo: Alvo, _ janela: NSWindow) {
        if (alvo.elemento as AnyObject).accessibilityPerformPress?() == true {
            return
        }
        // Sem ação de apertar: um clique de mouse no meio dele, dentro do app.
        let ponto = janela.convertPoint(fromScreen: alvo.centro)
        for tipo in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: tipo, location: ponto, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: janela.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                janela.sendEvent(e)
            }
        }
    }

    // MARK: - Rolagem

    /// Rola com um evento de roda do mouse no ponto dado, dentro do app: o
    /// ScrollView do SwiftUI (que já não é um NSScrollView) recebe como se a
    /// pessoa tivesse girado a roda ali em cima — vale para a página e para as
    /// fileiras que andam de lado.
    private func roda(em pontoNaTela: NSPoint, dx: CGFloat, dy: CGFloat) {
        // De lado vai como roda vertical com Shift, que é como o macOS (e o
        // ScrollView do SwiftUI) entende rolagem horizontal vinda de mouse.
        let lateral = dx != 0 && dy == 0
        guard let janela = janelaPrincipal(),
              let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                               wheel1: Int32((lateral ? dx : dy).rounded()), wheel2: 0, wheel3: 0) else { return }
        if lateral { cg.flags = .maskShift }
        // CGEvent mede de cima para baixo na tela principal.
        let alturaTela = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: pontoNaTela.x, y: alturaTela - pontoNaTela.y)
        guard let e = NSEvent(cgEvent: cg) else { return }
        janela.sendEvent(e)
    }

    /// Área útil da janela (sem a barra do topo), em coordenadas de tela.
    private func areaUtil(_ janela: NSWindow) -> NSRect {
        var r = janela.contentLayoutRect
        r = janela.convertToScreen(r)
        r.size.height -= 70
        return r
    }

    /// Rola meia tela na direção pedida, a partir de onde o foco está.
    private func rolar(_ origem: Alvo, _ direcao: Direcao) -> Bool {
        guard let janela = janelaPrincipal() else { return false }
        let area = areaUtil(janela)
        let v = area.height * 0.5, h = area.width * 0.5
        _ = h
        switch direcao {
        case .baixo: roda(em: origem.centro, dx: 0, dy: -v)
        case .cima: roda(em: origem.centro, dx: 0, dy: v)
        case .direita, .esquerda:
            // As fileiras do SwiftUI não aceitam roda de lado vinda de fora:
            // a fileira que está naquela altura anda uma página sozinha.
            let p = janela.convertPoint(fromScreen: origem.centro)
            let alturaConteudo = janela.contentView?.bounds.height ?? janela.frame.height
            NotificationCenter.default.post(name: .focoRemotoAndarFileira, object: nil,
                                            userInfo: ["y": alturaConteudo - p.y, "passo": direcao == .direita ? 1 : -1])
        }
        return true
    }

    /// Traz o escolhido inteiro para a vista: rola o que faltar, de lado
    /// (na fileira dele) e na vertical (a página).
    private func trazerParaAVista(_ alvo: Alvo) {
        guard let janela = janelaPrincipal() else { return }
        let area = areaUtil(janela).insetBy(dx: 16, dy: 16)
        let q = alvo.quadro
        var dx: CGFloat = 0, dy: CGFloat = 0
        if q.maxX > area.maxX { dx = -(q.maxX - area.maxX) } else if q.minX < area.minX { dx = area.minX - q.minX }
        if q.minY < area.minY { dy = area.minY - q.minY } else if q.maxY > area.maxY { dy = -(q.maxY - area.maxY) }
        _ = dx
        if dy != 0 { roda(em: alvo.centro, dx: 0, dy: -dy) }
    }

    // MARK: - Contorno

    private func mostrar(_ quadro: NSRect, _ janela: NSWindow) {
        let moldura = quadro.insetBy(dx: -4, dy: -4)
        let w: NSWindow
        if let contorno { w = contorno } else {
            w = NSWindow(contentRect: moldura, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.level = .floating
            w.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            let v = NSView()
            v.wantsLayer = true
            v.layer?.borderColor = NSColor.white.cgColor
            v.layer?.borderWidth = 3
            v.layer?.cornerRadius = 10
            v.layer?.shadowColor = NSColor.black.cgColor
            v.layer?.shadowOpacity = 0.6
            v.layer?.shadowRadius = 6
            w.contentView = v
            contorno = w
        }
        w.setFrame(moldura, display: true)
        if w.parent !== janela {
            w.parent?.removeChildWindow(w)
            janela.addChildWindow(w, ordered: .above)
        }
        w.orderFront(nil)
        // Some sozinho depois de um tempo parado, para não ficar na frente do mouse.
        apagar?.cancel()
        let tarefa = DispatchWorkItem { [weak self] in self?.contorno?.orderOut(nil) }
        apagar = tarefa
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: tarefa)
    }

    private func distancia(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

extension Notification.Name {
    /// O foco remoto chegou na borda de uma fileira: `y` (do topo do conteúdo
    /// da janela) diz qual fileira, `passo` (+1/−1) para que lado andar.
    static let focoRemotoAndarFileira = Notification.Name("saimo.focoRemotoAndarFileira")
}
