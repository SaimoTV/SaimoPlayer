import Foundation

/// Handlers HTTP de `/addons`, `/api/addons` e `POST /addons` servidos na porta 8999.
enum ConnectAddonsWeb {
    private final class CaixaResultado: @unchecked Sendable {
        var codigo = 200
        var motivo = "OK"
        var dados = Data()
    }

    static func estadoJSON() -> Data {
        let box = CaixaResultado()
        let semaforo = DispatchSemaphore(value: 0)
        Task { @MainActor in
            box.dados = serializarEstado()
            semaforo.signal()
        }
        semaforo.wait()
        return box.dados
    }

    static func processarPost(corpo: Data) -> (codigo: Int, motivo: String, dados: Data) {
        let obj = (try? JSONSerialization.jsonObject(with: corpo) as? [String: Any]) ?? [:]
        let acao = (obj["action"] as? String) ?? ((obj["url"] as? String) != nil ? "add" : "")

        let box = CaixaResultado()
        let semaforo = DispatchSemaphore(value: 0)

        Task { @MainActor in
            defer { semaforo.signal() }
            switch acao {
            case "add":
                let rawUrl = (obj["url"] as? String) ?? ""
                do {
                    _ = try await AddonStore.shared.instalar(url: rawUrl)
                    SaimoConnect.shared.avisarDados(atraso: 2)
                    box.dados = serializarEstado()
                } catch {
                    box.codigo = 400
                    box.motivo = "Bad Request"
                    box.dados = erroJSON(error.localizedDescription)
                }

            case "toggle":
                if let idStr = obj["id"] as? String, let uuid = UUID(uuidString: idStr) {
                    AddonStore.shared.alternar(id: uuid)
                    SaimoConnect.shared.avisarDados(atraso: 2)
                    box.dados = serializarEstado()
                } else {
                    box.codigo = 400
                    box.motivo = "Bad Request"
                    box.dados = erroJSON("ID de addon inválido.")
                }

            case "remove":
                if let idStr = obj["id"] as? String, let uuid = UUID(uuidString: idStr) {
                    AddonStore.shared.remover(id: uuid)
                    SaimoConnect.shared.avisarDados(atraso: 2)
                    box.dados = serializarEstado()
                } else {
                    box.codigo = 400
                    box.motivo = "Bad Request"
                    box.dados = erroJSON("ID de addon inválido.")
                }

            case "move":
                if let idStr = obj["id"] as? String, let uuid = UUID(uuidString: idStr),
                   let delta = obj["delta"] as? Int {
                    AddonStore.shared.mover(id: uuid, deslocamento: delta)
                    SaimoConnect.shared.avisarDados(atraso: 2)
                    box.dados = serializarEstado()
                } else {
                    box.codigo = 400
                    box.motivo = "Bad Request"
                    box.dados = erroJSON("Parâmetros de ordenação inválidos.")
                }

            case "debrid":
                if let debridObj = obj["debrid"] as? [String: Any] {
                    DebridStore.shared.aplicarConnect(debridObj)
                    SaimoConnect.shared.avisarDados(atraso: 2)
                    box.dados = serializarEstado()
                } else {
                    box.codigo = 400
                    box.motivo = "Bad Request"
                    box.dados = erroJSON("Dados de Debrid ausentes.")
                }

            default:
                box.codigo = 400
                box.motivo = "Bad Request"
                box.dados = erroJSON("Ação desconhecida.")
            }
        }

        semaforo.wait()
        return (box.codigo, box.motivo, box.dados)
    }

    @MainActor
    private static func serializarEstado() -> Data {
        let payload: [String: Any] = [
            "addons": AddonStore.shared.paraConnect(),
            "debrid": DebridStore.shared.paraConnect(incluirChaves: false),
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }

    private static func erroJSON(_ mensagem: String) -> Data {
        let dict: [String: Any] = ["error": mensagem]
        return (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{\"error\":\"erro\"}".utf8)
    }

    static func paginaHTML() -> Data {
        Data(htmlPagina.utf8)
    }

    private static let htmlPagina = """
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Saimo Player — Addons e Debrid</title>
<style>
  :root { color-scheme: dark; --bg:#121417; --card:#1b1f25; --line:#2c323b; --accent:#e50914; --text:#f3f4f6; --muted:#9ca3af; }
  * { box-sizing:border-box; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  body { margin:0; background:var(--bg); color:var(--text); padding:20px; }
  .wrap { max-width:680px; margin:0 auto; display:grid; gap:18px; }
  h1 { margin:0; font-size:22px; }
  p.sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:16px; display:grid; gap:12px; }
  .row { display:flex; gap:8px; align-items:center; }
  input[type=text], input[type=password] { flex:1; width:100%; background:#0e1013; color:var(--text); border:1px solid var(--line); border-radius:9px; padding:10px 12px; font-size:14px; }
  button { background:var(--accent); color:#fff; border:0; border-radius:9px; padding:10px 14px; font-weight:600; font-size:13px; cursor:pointer; }
  button.sec { background:#2b313a; }
  button.del { background:#3b1c20; color:#fda4af; }
  button:disabled { opacity:.55; cursor:default; }
  .addon { border:1px solid var(--line); border-radius:10px; padding:12px; display:grid; gap:8px; background:#14171c; }
  .title { font-weight:600; font-size:14px; }
  .url { font-family:ui-monospace,Menlo,monospace; font-size:11px; color:var(--muted); word-break:break-all; }
  .err { background:rgba(249,115,22,.14); border:1px solid rgba(249,115,22,.35); color:#fdba74; padding:10px 12px; border-radius:9px; font-size:13px; display:none; }
  .ok { color:#86efac; font-size:13px; display:none; }
  .prov { display:grid; gap:6px; border-top:1px solid var(--line); padding-top:10px; }
  label.chk { display:flex; align-items:center; gap:8px; font-size:13px; }
</style>
</head>
<body>
<div class="wrap">
  <div>
    <h1>Saimo Player — Addons e Debrid</h1>
    <p class="sub">Adicione manifestos HTTP Stremio (/manifest.json) ou stremio:// e configure chaves Debrid diretamente pelo navegador.</p>
  </div>

  <div class="card">
    <div class="title">Instalar addon Stremio</div>
    <div class="row">
      <input id="addonUrl" type="text" placeholder="https://.../manifest.json ou stremio://..." autocomplete="off">
      <button id="btnAdd" onclick="instalar()">Instalar</button>
    </div>
    <div id="errBox" class="err"></div>
    <div id="okBox" class="ok"></div>
  </div>

  <div class="card">
    <div class="title">Addons instalados (<span id="countAddons">0</span>)</div>
    <div id="listaAddons">Carregando…</div>
  </div>

  <div class="card">
    <div class="title">Serviços Debrid</div>
    <p class="sub" style="margin:0">Preencha apenas a chave dos provedores que você usa (deixe em branco para manter a chave atual).</p>
    <div id="debridBox"></div>
    <label class="chk">
      <input id="syncConnect" type="checkbox"> Sincronizar chaves Debrid via Saimo Connect
    </label>
    <div class="row">
      <button onclick="salvarDebrid()">Salvar Debrid</button>
      <span id="debridOk" class="ok">Salvo no Mac!</span>
    </div>
  </div>
</div>

<script>
const PROVEDORES = [
  { id:'torbox', nome:'TorBox' },
  { id:'realdebrid', nome:'Real-Debrid' },
  { id:'alldebrid', nome:'AllDebrid' },
  { id:'premiumize', nome:'Premiumize' }
];
let estadoAtual = { addons:[], debrid:{ sincronizarConnect:false, provedores:{} } };

async function carregar() {
  const res = await fetch('/api/addons');
  estadoAtual = await res.json();
  renderizar();
}

function renderizar() {
  const lista = document.getElementById('listaAddons');
  const addons = estadoAtual.addons || [];
  document.getElementById('countAddons').textContent = addons.length;
  if (!addons.length) {
    lista.innerHTML = '<div style="color:#9ca3af;font-size:13px">Nenhum addon instalado ainda.</div>';
  } else {
    lista.innerHTML = addons.map(a => {
      const nome = (a.manifest && a.manifest.name) || a.baseUrl;
      const ver = (a.manifest && a.manifest.version) ? ' v' + a.manifest.version : '';
      const url = a.baseUrl + '/manifest.json' + (a.query ? '?' + a.query : '');
      return `<div class="addon">
        <div class="row" style="justify-content:space-between">
          <div>
            <div class="title">${esc(nome)}${esc(ver)}</div>
            <div class="url">${esc(url)}</div>
          </div>
          <label class="chk">
            <input type="checkbox" ${a.enabled ? 'checked' : ''} onchange="acao({action:'toggle',id:'${a.id}'})"> Ativo
          </label>
        </div>
        <div class="row">
          <button class="sec" onclick="acao({action:'move',id:'${a.id}',delta:-1})">↑ Subir</button>
          <button class="sec" onclick="acao({action:'move',id:'${a.id}',delta:1})">↓ Descer</button>
          <button class="del" onclick="acao({action:'remove',id:'${a.id}'})">Remover</button>
        </div>
      </div>`;
    }).join('');
  }

  const provs = (estadoAtual.debrid && estadoAtual.debrid.provedores) || {};
  document.getElementById('syncConnect').checked = !!(estadoAtual.debrid && estadoAtual.debrid.sincronizarConnect);
  document.getElementById('debridBox').innerHTML = PROVEDORES.map(p => {
    const d = provs[p.id] || {};
    const ph = d.configured ? 'Chave já salva (deixe vazio para manter ou cole nova)' : 'Cole a API Key';
    return `<div class="prov">
      <label class="chk">
        <input type="checkbox" id="en_${p.id}" ${d.enabled ? 'checked' : ''}> <strong>${p.nome}</strong>
      </label>
      <input type="password" id="key_${p.id}" placeholder="${ph}" autocomplete="off">
    </div>`;
  }).join('');
}

async function acao(payload) {
  const err = document.getElementById('errBox');
  err.style.display = 'none';
  const res = await fetch('/addons', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  const data = await res.json();
  if (!res.ok) {
    err.textContent = data.error || 'Erro ao atualizar.';
    err.style.display = 'block';
    return false;
  }
  estadoAtual = data;
  renderizar();
  return true;
}

async function instalar() {
  const inp = document.getElementById('addonUrl');
  const btn = document.getElementById('btnAdd');
  const ok = document.getElementById('okBox');
  ok.style.display = 'none';
  btn.disabled = true;
  const sucesso = await acao({ action:'add', url: inp.value });
  btn.disabled = false;
  if (sucesso) {
    inp.value = '';
    ok.textContent = 'Addon instalado com sucesso!';
    ok.style.display = 'block';
  }
}

async function salvarDebrid() {
  const provedores = {};
  for (const p of PROVEDORES) {
    const enabled = document.getElementById('en_' + p.id).checked;
    const keyVal = document.getElementById('key_' + p.id).value.trim();
    provedores[p.id] = keyVal ? { enabled, apiKey: keyVal } : { enabled };
  }
  const ok = await acao({
    action: 'debrid',
    debrid: {
      sincronizarConnect: document.getElementById('syncConnect').checked,
      provedores
    }
  });
  if (ok) {
    const tag = document.getElementById('debridOk');
    tag.style.display = 'inline';
    setTimeout(() => { tag.style.display = 'none'; }, 2200);
  }
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

carregar();
</script>
</body>
</html>
"""
}
