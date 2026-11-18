# Perfis no Saimo TV

Contrato comum dos apps (TV Box, celular, Mac, Windows/Linux, Roku e site,
que também é o app da Samsung e da LG). Mudou aqui, muda em todos.

## O que é um perfil

```json
{ "id": "principal", "nome": "Gabriel", "avatar": "gato", "em": 1795000000000 }
```

- `id`: `principal` para o perfil que já existia antes dos perfis; os outros
  ganham um id aleatório de 10 letras e números (`p` + 9, ex. `pk3x9a2mzq`),
  criado uma vez e nunca trocado. É o id que casa o perfil entre aparelhos.
- `nome`: até 20 caracteres, sem quebra de linha. O principal começa como
  "Principal" (o usuário renomeia).
- `avatar`: id de `docs/avatares/ids.txt` (ex. `gato`). Id desconhecido (app
  antigo recebendo avatar novo): mostra a inicial do nome sobre o fundo padrão.
- `em`: quando nome ou avatar mudaram por último (ms desde 1970). Vale o maior.
- No máximo **10 perfis** por aparelho, contando o principal. O principal não
  pode ser apagado.

## Perfil Kids

```json
{ "id": "pk3x9a2mzq", "nome": "Léo", "avatar": "dino", "em": 1795000000000,
  "kids": true, "codigo": "<sha256 hex>" }
```

- `kids: true` marca o perfil infantil. O principal nunca é Kids.
- `codigo`: SHA-256 (hex, minúsculo) de `saimo-kids:<id>:<4 dígitos>`. O código
  em si nunca é guardado nem enviado. Viaja pelo Connect com o perfil: o Kids
  fica trancado com o mesmo código em todos os aparelhos.
- Pede o código: sair do Kids (escolher outro perfil), editar ou apagar o
  perfil Kids e abrir os Ajustes estando no Kids. Errou: nada acontece, avisa.
- No Kids aparece:
  - **Ao vivo, rádios e eventos**: tudo, menos o que é adulto (grupo ou nome
    adulto, a seção restrita). O modo adulto não destranca no Kids, nem com o
    código do controle parental (o controle parental em si não muda).
  - **Filmes e séries**: só títulos com classificação indicativa conhecida de
    Livre, 10 ou 12 anos. Sem classificação ou 14+: escondido (grades,
    fileiras, busca, continuar assistindo, favoritos).
- Criar perfil Kids: nome, avatar e o código (digitado duas vezes).

## O que é de cada perfil e o que é compartilhado

| De cada perfil | Compartilhado (o aparelho todo) |
|---|---|
| canais favoritos | endereços das listas e Minhas listas |
| títulos favoritos (filmes e séries) | fontes desativadas, addons, contas de debrid |
| onde parou / continuar assistindo | ajustes do app (zero delay, áudio, legenda padrão...) |
| último canal assistido | pareamento e celulares de confiança do Saimo Connect |
| canais, rádios e buscas recentes | atualização, telemetria, controle parental |
| lembretes de programa | downloads (arquivos no aparelho) |

Regra de armazenamento em todos os apps: **o perfil principal usa exatamente as
chaves e arquivos de antes** (quem atualiza não perde nada e não há migração);
os outros perfis usam a mesma chave com o sufixo `@<id>` (ou uma pasta
`perfis/<id>/`, onde o app guarda em arquivos). Apagar um perfil apaga os dados
dele.

A lista de perfis e o perfil ativo ficam fora dos dados de perfil:
`perfis` (lista, JSON) e `perfil-ativo` (id). O perfil ativo é do aparelho e
não viaja pelo Connect.

## Escolher o perfil

- Com 2 ou mais perfis, o app abre em **"Quem está assistindo?"**: a grade de
  avatares e nomes, mais "Gerenciar perfis". Com 1 perfil, o app abre como
  sempre.
- Ajuste "Perguntar o perfil ao abrir" (ligado por padrão). Desligado, abre no
  último perfil usado.
- O avatar do perfil ativo fica no topo (menu ou barra) e leva à troca.
- Gerenciar: criar (nome + avatar), renomear, trocar avatar, apagar (com
  confirmação, nunca o principal). Ao chegar a 10, "Adicionar perfil" some.
- Trocar de perfil recarrega favoritos, progresso e recentes; o vídeo que
  estava tocando para.

## Saimo Connect (`{"t":"dados"}`)

O pacote continua com os campos de sempre (`progresso`, `favTitulos`,
`favCanais`, `listas`, `addons`...), **preenchidos com os dados do perfil
principal**, para apps antigos seguirem funcionando. E ganha:

```json
"perfis": [
  { "id": "principal", "nome": "Gabriel", "avatar": "gato", "em": 1795000000000,
    "progresso": [...], "favTitulos": [...], "favCanais": [...] },
  { "id": "pk3x9a2mzq", "nome": "Ana", "avatar": "coelho", "em": 1795000100000,
    "progresso": [...], "favTitulos": [...], "favCanais": [...] }
],
"perfisRemovidos": [ { "id": "pq81ab2c0d", "em": 1795000200000 } ]
```

`progresso`, `favTitulos` e `favCanais` de cada perfil têm o mesmo formato de
antes. Ao receber:

1. `perfisRemovidos`: perfil local com o mesmo id e `em` menor que o da remoção
   é apagado (com os dados). A remoção é guardada (até 50, as mais novas) para
   ser repassada.
2. Para cada perfil recebido (que não esteja removido aqui depois do `em`
   dele): se não existe aqui e há vaga (menos de 10), é criado; se existe, nome
   e avatar ficam com o `em` maior. Sem vaga, o perfil é ignorado.
3. Os dados de cada perfil são juntados aos do perfil de mesmo id, com as
   regras de sempre: progresso vale o mais recente; favoritos ficam com a união.
4. Pacote sem `perfis` (app antigo): os campos de sempre vão para o perfil
   principal, como antes.

Cada lado manda todos os perfis, então o celular e a TV ficam com os mesmos
perfis e cada um com os seus favoritos e onde parou, qualquer que seja o
perfil aberto em cada aparelho.

`kids` e `codigo` viajam junto com nome e avatar (mesmo `em`).

O Roku não sincroniza dados pelo Connect (só controle remoto): lá os perfis
ficam no aparelho. No Roku o Kids também esconde filmes e séries por inteiro:
a classificação de cada título não cabe na memória de um stick de 512 MB, e
esconder tudo é o lado seguro.

## Avatares

`scripts/avatares/gerar.py` gera `docs/avatares/<id>.svg` e `png/<id>.png`
(256 px). Cada app leva uma cópia (site: `public/avatares/*.svg`; apps nativos:
os PNG). Ids nunca são renomeados; avatar novo entra no fim da lista.

## Conta Saimo

A Conta Saimo (opcional) leva este mesmo pacote para a nuvem: ver `docs/conta.md`.
