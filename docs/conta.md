# Conta Saimo (opcional)

Login opcional para guardar perfis, onde parou, favoritos, listas e addons
na nuvem e ter tudo em qualquer aparelho. **Sem conta, nada muda**: os dados
ficam no aparelho e o Saimo Connect segue funcionando na rede de casa. Nenhuma
tela pede login; a conta só aparece em Ajustes > Conta Saimo (fora do perfil
Kids).

Servidor: repositório `SaimoConta` (Cloudflare Worker + D1). A API está no
README de lá.

## Como entrar

| Jeito | Onde | Como |
|---|---|---|
| E-mail e senha | todos os apps e o site | "Criar conta" ou "Entrar"; o e-mail não é verificado (é só o login) |
| QR na TV | TV Box, Samsung/LG, Mac, Windows/Linux, Roku | a TV mostra QR e código `ABCD-2345`; o celular ou o site logado aprova |

- E-mail que já tem conta não é cadastrado de novo (entra com a senha).
- **Trocar a senha** (logado, com a senha atual): os outros aparelhos saem.
  Esqueceu a senha: num aparelho onde a conta já está aberta, troque por lá.
- O código por e-mail existe no servidor mas está desligado (sem envio de
  e-mail configurado); os apps não mostram.
- Rotas de senha, cadastro e código da TV: no máximo 20 pedidos por minuto por IP.
- Senha: 8 a 128 caracteres, guardada como PBKDF2-SHA256 (100 mil iterações).
  5 erros seguidos travam o login com senha por 15 min.
- O QR leva a `https://saimo-tv.com.br/conectar?c=ABCD2345`: com a conta
  aberta no navegador, um toque aprova a TV; sem conta, entra ali mesmo.
  No celular, Ajustes > Conta Saimo > Entrar numa TV aceita o código digitado.
- Na TV, o código vence em 10 min; a TV pergunta a cada 8 s nos 2 primeiros
  minutos (o servidor diz em `intervalo`), depois a cada 15 s e, passados 5 min,
  a cada 20 s; com o app atrás de outro, não pergunta. Venceu, para de perguntar e mostra "Gerar novo
  código" (desde a 3.3.3; antes trocava sozinho para sempre e uma tela
  esquecida aberta gerava pedidos sem fim). Aba escondida não pergunta.
- Pedidos sem sessão do site vão com `Content-Type: text/plain` (sem OPTIONS
  antes de cada um); o servidor manda `access-control-max-age: 86400`.

## O que sincroniza

O mesmo pacote do Saimo Connect (`{"t":"dados"}`, ver `docs/perfis.md`):
perfis (com Kids), onde parou, títulos e canais favoritos de cada perfil,
listas (os dois endereços e as Minhas listas de link) e addons/Debrid. O
servidor junta com as mesmas regras do Connect: progresso vale o mais novo,
favoritos ficam com a união, perfis por id com o `em` maior, remoções valem
sobre perfis mais antigos. Desde a 3.3.3, o que foi removido ("Continue
assistindo", favoritos, Minhas listas) viaja como remoção e não volta pela
união (ver "Remoções" em `docs/perfis.md`). Progresso e favoritos sem ano (Samsung/LG) se
juntam ao mesmo título com ano.

| App | Perfis | Onde parou | Favoritos | Listas | Addons |
|---|---|---|---|---|---|
| Celular, TV Box, Mac, Windows/Linux | sim | sim | sim | sim | sim |
| Site | sim | sim (o que foi visto a partir desta versão) | sim | sim | sim |
| Samsung/LG | sim | sim | sim | Minhas listas | sim |
| Roku | sim | sim | sim | não | não |

Quando sincroniza: ao abrir o app, ao voltar para ele (mais de 1 min depois),
alguns segundos depois de uma mudança (no máximo uma vez a cada 5 min; ao sair
do app ou esconder a aba, o que falta vai na hora) e a cada 15 minutos com o
app na frente (desde a 3.3.5). **Um pedido por sincronia** (cada pedido é cobrado): com
mudança aqui, só o `PUT` (o servidor devolve tudo já juntado); sem mudança, só
o `GET`.

**Listas importadas de arquivo** (M3U escolhido no aparelho) não sincronizam:
só as adicionadas por link e os dois endereços. Os dados ficam
criptografados no servidor (AES-GCM), até 2 MB por conta.

## Sair e apagar

- **Sair** encerra a sessão só naquele aparelho; os dados continuam nele.
- **Apagar conta** (celular e site) apaga a conta e tudo o que ela guarda no
  servidor; os dados dos aparelhos continuam neles.

## Endereço do servidor por app

Produção: `https://conta.saimo-tv.com.br` (Worker `saimo-conta` + D1 `saimo-conta`, conta Cloudflare gabrielsaimo97). A chave que cifra os dados (`CHAVE_DADOS`) tem cópia em `~/Library/Application Support/SaimoTV/conta-chave-dados.txt`: sem ela os dados guardados não abrem. Para testar com
o servidor local (`npm run dev` no SaimoConta):

| App | Teste |
|---|---|
| Celular | `EXPO_PUBLIC_CONTA_API=http://10.0.2.2:8787` no build |
| TV Box | build de depuração já usa `http://10.0.2.2:8787` |
| Site e Samsung/LG | `VITE_CONTA_API=http://127.0.0.1:8787` no `vite` |
| Mac e Windows/Linux | `SAIMO_CONTA_API=http://127.0.0.1:8787` no ambiente |
| Roku | chave `conta_api` no registro do canal |
