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
| Código no e-mail | celular, site | 6 números, valem 10 min, 1 pedido por minuto |
| E-mail e senha | celular, site, Mac, Windows/Linux, TV Box, Samsung/LG, Roku | quem criou uma senha |
| QR na TV | TV Box, Samsung/LG, Mac, Windows/Linux, Roku | a TV mostra QR e código `ABCD-2345`; o celular ou o site logado aprova |

- **Criar ou trocar a senha** pede sempre o código do e-mail (prova que o
  e-mail é da pessoa). Fica no celular e no site; as TVs só entram com a senha.
  Trocar uma senha que já existia tira a conta dos outros aparelhos.
- Senha: 8 a 128 caracteres, guardada como PBKDF2-SHA256 (100 mil iterações).
  5 erros seguidos travam o login com senha por 15 min.
- O QR leva a `https://saimo-tv.com.br/conectar?c=ABCD2345`: com a conta
  aberta no navegador, um toque aprova a TV; sem conta, entra ali mesmo.
  No celular, Ajustes > Conta Saimo > Entrar numa TV aceita o código digitado.
- Na TV, o código vence em 10 min e é trocado sozinho; a TV pergunta a cada 5 s.

## O que sincroniza

O mesmo pacote do Saimo Connect (`{"t":"dados"}`, ver `docs/perfis.md`):
perfis (com Kids), onde parou, títulos e canais favoritos de cada perfil,
listas (os dois endereços e as Minhas listas de link) e addons/Debrid. O
servidor junta com as mesmas regras do Connect: progresso vale o mais novo,
favoritos ficam com a união, perfis por id com o `em` maior, remoções valem
sobre perfis mais antigos. Progresso e favoritos sem ano (Samsung/LG) se
juntam ao mesmo título com ano.

| App | Perfis | Onde parou | Favoritos | Listas | Addons |
|---|---|---|---|---|---|
| Celular, TV Box, Mac, Windows/Linux | sim | sim | sim | sim | sim |
| Site | sim | sim (o que foi visto a partir desta versão) | sim | sim | sim |
| Samsung/LG | sim | sim | sim | Minhas listas | sim |
| Roku | sim | sim | sim | não | não |

Quando sincroniza: ao abrir o app, ao voltar para ele (mais de 1 min depois),
alguns segundos depois de uma mudança e a cada 10 minutos. Os dados ficam
criptografados no servidor (AES-GCM), até 2 MB por conta.

## Sair e apagar

- **Sair** encerra a sessão só naquele aparelho; os dados continuam nele.
- **Apagar conta** (celular e site) apaga a conta e tudo o que ela guarda no
  servidor; os dados dos aparelhos continuam neles.

## Endereço do servidor por app

Produção: `https://conta.saimo-tv.com.br` (ainda não criado). Para testar com
o servidor local (`npm run dev` no SaimoConta):

| App | Teste |
|---|---|
| Celular | `EXPO_PUBLIC_CONTA_API=http://10.0.2.2:8787` no build |
| TV Box | build de depuração já usa `http://10.0.2.2:8787` |
| Site e Samsung/LG | `VITE_CONTA_API=http://127.0.0.1:8787` no `vite` |
| Mac e Windows/Linux | `SAIMO_CONTA_API=http://127.0.0.1:8787` no ambiente |
| Roku | chave `conta_api` no registro do canal |
