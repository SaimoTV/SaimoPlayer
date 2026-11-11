# Formato de lista do Saimo

Este documento descreve, arquivo por arquivo, como montar **a sua própria lista de
canais e de filmes e séries** para o Saimo reconhecer. É o mesmo formato que os
apps (Mac, Windows, Linux, Android, TV Box, Roku, Samsung e LG) e o site leem.

> O Saimo é um reprodutor. Ele não traz nem hospeda conteúdo: só abre o que está
> na lista que **você** informa. Use apenas endereços de conteúdo que você tem
> direito de acessar.

## Sumário

1. [Antes de começar: três jeitos de trazer uma lista](#1-antes-de-começar-três-jeitos-de-trazer-uma-lista)
2. [Como funciona](#2-como-funciona)
3. [Onde publicar](#3-onde-publicar)
4. [Canais](#4-canais)
5. [Filmes e séries](#5-filmes-e-séries)
6. [Referência rápida](#6-referência-rápida)
7. [Validar antes de usar](#7-validar-antes-de-usar)
8. [Erros comuns](#8-erros-comuns)

---

## 1. Antes de começar: três jeitos de trazer uma lista

| Jeito | Para quem | O que digitar no app |
|---|---|---|
| **Link M3U** | Você já tem uma lista `.m3u` | Só o link (em *Minhas listas*) |
| **Servidor + usuário + senha (Xtream)** | Seu provedor entrega esses dados | Servidor, usuário e senha (usuário e senha só se o provedor exigir) |
| **Formato Saimo** *(este documento)* | Você quer controlar tudo: várias fontes por canal, reserva automática, capas, fileiras, séries por temporada | Dois endereços: um de **canais** e um de **filmes e séries** (em *Ajustes → Listas*) |

M3U e Xtream entram por *Minhas listas* e trazem **canais ao vivo**. O formato Saimo
é o único que entrega o acervo completo de **filmes e séries** (navegação por letra,
busca, destaques, temporadas). Tudo abaixo é sobre ele.

## 2. Como funciona

Você publica **arquivos de texto** em um endereço da internet. No app, em
*Ajustes → Listas*, informa dois endereços:

- **Canais:** `https://seu-site/canais/`
- **Filmes e séries:** `https://seu-site/filmes/`

O app só **acrescenta o nome do arquivo** ao endereço: `…/canais/` + `catalogo.txt`.
Por isso:

- o endereço **começa com `https://` e termina com `/`**. Alguns apps completam sozinhos o que faltar (o Mac, o Roku), mas não conte com isso;
- os dois endereços podem ser o mesmo, com os arquivos na mesma pasta, ou diferentes;
- um arquivo opcional ausente não dá erro: aquele recurso só não aparece;
- trocar um link dentro de um arquivo basta: os apps leem a lista **a cada abertura**
  (no Mac os filmes ficam em cache por até 3 horas e os destaques por 15 minutos).

Regras gerais de **todos** os arquivos:

- texto **UTF-8**, sem BOM, de preferência com quebra de linha **LF**;
- linhas em branco são ignoradas; linhas começadas por `#` são comentários
  (exceção: no `indice.txt`, a linha da letra `#` começa com `#` + TAB — ver abaixo);
- onde se diz **TAB**, é o caractere de tabulação (não espaços);
- endereços de vídeo completos: `https://…` ou `http://…`.

Há exemplos prontos em [`docs/exemplos/`](exemplos/): copie, troque os endereços e
publique.

## 3. Onde publicar

Qualquer hospedagem de **arquivos estáticos** serve: Cloudflare Pages, GitHub Pages,
Netlify, Vercel, um servidor próprio com nginx. Exigências:

| Exigência | Por quê |
|---|---|
| **HTTPS** | O site e as TVs Samsung/LG bloqueiam endereços `http://` em páginas seguras |
| **CORS aberto** (`Access-Control-Allow-Origin: *`) | O site e as TVs Samsung/LG são páginas web e só leem arquivos que permitem. Os apps nativos (Mac, Windows, Android, Roku) não dependem disso |
| Tipo `text/plain` (ou `text/*`) | Alguns navegadores recusam outros tipos |
| Sem login, sem redirecionamento para página de aviso | O app não sabe preencher |

**Cloudflare Pages** e **Netlify**: crie na pasta publicada um arquivo `_headers`:

```
/*
  Access-Control-Allow-Origin: *
  Content-Type: text/plain; charset=utf-8
```

**GitHub Pages** já envia `Access-Control-Allow-Origin: *`.

Teste abrindo `https://seu-site/canais/catalogo.txt` no navegador: deve aparecer o
texto puro. Depois rode o [validador](#7-validar-antes-de-usar).

---

## 4. Canais

Endereço de canais + estes arquivos:

| Arquivo | Obrigatório | Para quê |
|---|---|---|
| `catalogo.txt` | **sim** | A lista de canais, com fontes, reservas e chaves |
| `radios.txt` | não | A aba Rádios |
| `guia.txt` | não | Guia de programação (o que passa agora e a seguir) |
| `canais.txt` | não | Canais extras em M3U, que entram como reserva do catálogo |
| `restritos.txt` | não | Canais que só aparecem depois do desbloqueio por código (mesmo formato do catálogo) |

### 4.1 `catalogo.txt`

Um campo por linha, no formato `chave: valor`. Um `canal:` começa um canal novo; o
que vem depois pertence a ele.

```
canal: Canal de Exemplo
logo: https://example.com/logos/canal-exemplo.png
categoria: TV Aberta
fonte: https://example.com/canal-exemplo/principal.m3u8
nome: Principal
fonte: https://example.com/canal-exemplo/reserva.m3u8
nome: Reserva
```

| Chave | Obrigatória | O que é |
|---|---|---|
| `canal:` | sim | Nome do canal. Abre um canal novo. Canais com o mesmo nome (ignorando maiúsculas e "HD") são tratados como o mesmo |
| `fonte:` | **sim, ao menos uma** | Endereço do vídeo. A primeira é a preferida; se ela falhar, o player **desce para a seguinte** sozinho |
| `logo:` | não | Imagem do canal (PNG/JPG/WebP, https) |
| `categoria:` | não | Seção da lista (ver abaixo). Sem ela, o app deduz pelo nome do canal |
| `nome:` | não | Rótulo da fonte acima ("Principal", "Legendado", "Temporada 3"). Aparece no lugar de "Fonte 2" |
| `qualidade:` | não | Marca de qualidade da fonte ("4K", "HD") |
| `referer:` | não | Cabeçalho `Referer` que o servidor da fonte exige |
| `agente:` | não | `User-Agent` que o servidor da fonte exige |
| `chave:` | não | Chave **ClearKey** das fontes DASH (`.mpd`), no formato `KID:CHAVE` (32 hexadecimais cada) |

`nome:`, `qualidade:`, `referer:`, `agente:` e `chave:` **pertencem à fonte
imediatamente acima**, não ao canal. Por isso precisam vir **depois** de um `fonte:`.

**Categorias padrão** (escreva exatamente assim):
`TV Aberta`, `Filmes e Séries`, `Esportes`, `Notícias`, `Infantil`, `Documentários`,
`Pluto TV`, `24 Horas`, `Variedades`, `Músicas`, `Adulto`. Uma categoria diferente
funciona no Roku (vira uma seção própria); nos demais apps cai na regra do nome do canal.

**Tipos de fonte aceitos:** HLS (`.m3u8`), MPEG-TS (`.ts`), MP4 e DASH (`.mpd`, com
`chave:` quando protegido). Cada app reproduz o que o sistema dele suporta; o HLS é o
mais compatível.

**Ordem importa:** o canal aparece na ordem do arquivo dentro de cada seção, e a
numeração dos canais segue essa ordem.

### 4.2 `radios.txt`

Uma rádio por linha, separando os campos com `|`:

```
Rádio Exemplo FM|https://example.com/radio/exemplo.mp3|https://example.com/logos/radio-exemplo.png
Rádio Sem Logo|https://example.com/radio/sem-logo.aac
```

`nome|endereço[|logo]`. O endereço deve começar com `http`. Nomes repetidos: vale a
primeira. **Atenção:** se o arquivo tiver **menos de 10 rádios** válidas, o Mac o trata
como incompleto e mantém a lista anterior; mantenha 10 ou mais.

O app agrupa as rádios por estilo (Rock, Notícias e esporte, Gospel, Pop, Sertanejo/MPB,
Clássica e jazz) a partir de palavras no **nome** — nomeie "Rock de Exemplo", não só
"Exemplo FM", se quiser que ela caia no estilo certo.

### 4.3 `guia.txt`

Liga cada canal à programação. Campos separados por **TAB**:

| Linha | Significado |
|---|---|
| `meuguia`⇥`nome do canal no catálogo`⇥`código no meuguia.tv` | Programação do canal vinda do meuguia.tv |
| `guiadetv`⇥`nome normalizado`⇥`endereço no guiadetv.com` | Idem, do guiadetv.com |
| `alias`⇥`nome normalizado`⇥`nome do canal no feed XMLTV` | Diz que o canal "X" é o "Y" de um feed XMLTV |
| `feed`⇥`-`⇥`endereço de um feed XMLTV` | Um feed XMLTV completo (vale a ordem) |
| `pluto`⇥`-`⇥`endereço do guia da Pluto TV` | Guia da Pluto TV |

Sem `guia.txt`, o guia sai só do que casa por nome com os feeds do próprio app.

### 4.4 `canais.txt` (extras em M3U)

Um M3U comum (`#EXTM3U`, `#EXTINF` com `tvg-id`, `tvg-logo`, `group-title`). Como
M3U não guarda chave nem cabeçalhos, esses canais entram **como reserva**: se o nome
(normalizado) já existe no `catalogo.txt`, a fonte do M3U vira uma fonte extra no fim
daquele canal; se não existe, entra como canal novo no fim da lista.

---

## 5. Filmes e séries

Endereço de filmes + estes arquivos. O acervo é **fatiado por letra** para que nenhum
download passe de uns 100 KB: a tela navega por letra, e o app baixa só a fatia que
o usuário abre.

| Arquivo | Obrigatório | Para quê |
|---|---|---|
| `indice.txt` | **sim** | Os servidores (bases) e a contagem por letra |
| `filmes-<LETRA>.txt` | **sim** (um por letra com filmes) | Os filmes da letra e suas fontes |
| `series-<LETRA>.txt` | sim, se houver séries | A lista de séries da letra |
| `series-<LETRA>-<N>.txt` | sim, se houver séries | Os episódios, em pedaços |
| `busca.txt` | recomendado | Busca no acervo inteiro |
| `destaques.txt` | recomendado | As fileiras da tela inicial |
| `fichas.txt`, `generos.txt`, `detalhes.txt` | não | Capas, gêneros, ano, nota e classificação (filtros) |
| `marcas.txt` | não | Qualidade (4K/FHD/HD) por fonte |
| `redeflix/links-animes.txt`, `redeflix/links-doramas.txt` | não | Animes e doramas (título e episódios no mesmo arquivo) |

### 5.1 A letra de um título

A letra é a **primeira letra do título, sem acento, em maiúscula**: "Ágata" → `A`,
"Éramos Seis" → `E`. Títulos que começam com número, símbolo ou outro alfabeto vão
em **`#`**. Todos os arquivos por letra seguem essa regra; um título na letra errada
aparece no lugar errado e a busca não o acha.

O arquivo da letra `#` chama-se `filmes-#.txt` (na rede o app pede `filmes-%23.txt`,
que o servidor entende como `#`; se o seu servidor tiver problema com isso, confira
no navegador que `…/filmes-%23.txt` abre).

### 5.2 `indice.txt`

```
base: 0 https://example.com/movie/usuario/senha/
base: 1 https://example.com/series/usuario/senha/
#	1	0	0
A	2	1	0
F	1	0	0
```

**Linhas `base:`** — `base: <número> <endereço>`. São os **servidores** de onde
saem os vídeos. Numere em sequência a partir de **0**. Servem para encurtar os
arquivos: em vez de repetir `https://example.com/movie/usuario/senha/` em 30 mil
linhas, cada fonte escreve só `0:1001`. O endereço da base deve terminar com `/`.

**Linhas de letra** — quatro colunas separadas por **TAB**:

| Coluna | O que é |
|---|---|
| 1 | A letra (`A`–`Z` ou `#`) |
| 2 | Quantos filmes há em `filmes-<letra>.txt` |
| 3 | Quantas séries há em `series-<letra>.txt` |
| 4 | *(opcional)* quantos itens "reservados" (use `0`) |

Letras com `0` filmes **e** `0` séries podem ser omitidas.

> **Importante:** o índice é o único arquivo que dá sentido aos demais, porque cada
> fonte guarda o **número** da base, não o endereço. O app baixa o índice **a cada
> abertura**. Se você reordenar as bases, regere todos os arquivos junto.

### 5.3 `filmes-<LETRA>.txt`

Um filme por linha, com campos separados por **TAB**:

```
A Casa de Exemplo (2026)⇥dub=0:1001,https://example.com/espelho/casa.mp4⇥leg=0:1002
Aventura de Exemplo⇥dub=https://example.com/aventura.mp4
```

`título`⇥`versão=fontes`[⇥`versão=fontes`]

- **Título:** o texto exibido. Pode trazer o ano entre parênteses; escreva
  **exatamente igual** ao usado em `busca.txt`, `destaques.txt` e `fichas.txt`.
- **Versão:** `dub` (dublado) ou `leg` (legendado). Um filme pode ter uma ou as duas.
- **Fontes:** uma ou mais, separadas por **vírgula**; a primeira é a preferida e as
  seguintes são reserva. Cada fonte é:
  - um endereço completo (`https://…/arquivo.mp4`), **ou**
  - `<base>:<resto>`, como `0:1001`. O app cola o resto na base 0. Se o resto **não
    tem ponto**, ganha `.mp4`: `0:1001` vira `…/movie/usuario/senha/1001.mp4`. Se tem
    (`1001.mkv`), é usado como está.
- Uma linha sem nenhuma fonte válida é ignorada.

### 5.4 `series-<LETRA>.txt` e os pedaços

Uma série por linha (**TAB**): `título`⇥`ano`⇥`pedaço`⇥`episódios`

```
A Série de Exemplo⇥2025⇥0⇥3
```

| Coluna | O que é |
|---|---|
| título | Nome da série, **sem** o ano |
| ano | Ano (pode ficar vazio, mas mantenha o TAB) |
| pedaço | Número do arquivo de episódios onde ela está (`0`, `1`, `2`…) |
| episódios | Quantos episódios ela tem (só informativo) |

Os episódios ficam em `series-<LETRA>-<pedaço>.txt`. Agrupe várias séries por
arquivo até uns 100 KB (o app baixa o pedaço inteiro ao abrir uma série). Cada série
começa com um cabeçalho `@título⇥ano` e segue com um episódio por linha:

```
@A Série de Exemplo⇥2025
1⇥1⇥dub⇥1:9001,https://example.com/espelho/s01e01.mp4
1⇥1⇥leg⇥1:9002
1⇥2⇥dub⇥1:9003
2⇥1⇥dub⇥1:9004
```

`temporada`⇥`episódio`⇥`versão`⇥`fontes` — as fontes seguem as mesmas regras do
filme (endereço completo ou `base:resto`; a série usa em geral a base de séries,
a `1` do exemplo). O **título e o ano do `@` devem ser idênticos** aos de
`series-<LETRA>.txt`.

### 5.5 `busca.txt` (busca no acervo inteiro)

Uma linha por título, **TAB**: `título`⇥`f` ou `s`⇥`letra`[⇥`ano`]

```
A Casa de Exemplo (2026)⇥f⇥A⇥2026
A Série de Exemplo⇥s⇥A⇥2025
```

`f` filme, `s` série. Sem este arquivo a busca geral não acha nada (a navegação por
letra continua funcionando).

### 5.6 `destaques.txt` (fileiras da tela inicial)

```
capa: https://image.tmdb.org/t/p/w342
fila⇥Em alta
f⇥A Casa de Exemplo (2026)⇥A⇥2026⇥/caminho-do-poster.jpg
s⇥A Série de Exemplo⇥A⇥2025⇥/outro-poster.jpg
fila⇥Para a família
f⇥Filme de Exemplo (2024)⇥F⇥2024⇥https://example.com/capas/filme.jpg
```

- `capa:` — endereço-base das capas.
- `fila⇥Nome` — abre uma fileira.
- Itens: `tipo`⇥`título`⇥`letra`⇥`ano`⇥`capa`[⇥`trailer`].
  - `tipo`: `f` filme, `s` série, `a` anime, `d` dorama.
  - `capa`: caminho começando em `/` (junta com `capa:`) **ou** endereço completo.
  - Para séries, o título é o **nome sem o ano**; o ano vai na coluna própria.

### 5.7 Arquivos opcionais de enriquecimento

Todos com colunas por **TAB**; linhas `#` são comentário.

| Arquivo | Colunas |
|---|---|
| `fichas.txt` | `tipo` `título` `id TMDB` `capa` `gêneros separados por vírgula` (linha `capa:` define a base) |
| `generos.txt` | `tipo` `título` `gêneros separados por vírgula` |
| `detalhes.txt` | `tipo` `título` `ano` `nota 0–10` `classificação (L/10/12/14/16/18)` `popularidade` |
| `marcas.txt` | `base:resto` `qualidade` (`4k`, `fhd`, `hd`, `sd`) — as fontes 4K passam à frente |

Sem eles o app funciona; só não oferece filtros de gênero, ano, idade e nota.

### 5.8 Animes e doramas

`redeflix/links-animes.txt` e `redeflix/links-doramas.txt` juntam, num único arquivo,
o que o acervo normal separa em dois: cada série começa com `@título⇥ano⇥id` e traz
os episódios no formato `temporada⇥episódio⇥versão⇥fontes` (igual ao item 5.4).

---

## 6. Referência rápida

```
canais/                         filmes/
├── catalogo.txt   (obrigatório)├── indice.txt          (obrigatório)
├── radios.txt                  ├── filmes-A.txt … filmes-Z.txt, filmes-#.txt
├── guia.txt                    ├── series-A.txt …      (se houver séries)
├── canais.txt     (M3U)        ├── series-A-0.txt …    (episódios)
└── restritos.txt               ├── busca.txt, destaques.txt
                                ├── fichas.txt, generos.txt, detalhes.txt, marcas.txt
                                └── redeflix/links-animes.txt, links-doramas.txt
```

| Quero… | Faça |
|---|---|
| Só testar | Publique `catalogo.txt` com um canal e informe o endereço em *Ajustes → Listas* |
| Uma reserva automática | Acrescente outro `fonte:` abaixo do canal |
| Canal que exige cabeçalho | `referer:` / `agente:` logo abaixo da `fonte:` |
| Canal protegido (DASH) | `fonte:` com `.mpd` + `chave:` `KID:CHAVE` |
| Dublado e legendado do mesmo filme | Duas colunas na mesma linha: `dub=…` e `leg=…` |
| Trocar um servidor inteiro | Troque a linha `base:` no `indice.txt`: todos os filmes que usam aquele número passam a apontar para o novo |

## 7. Validar antes de usar

O repositório traz um validador que lê a sua lista (de uma pasta do computador ou do
endereço já publicado) e aponta cada problema com o arquivo e a linha:

```bash
python3 scripts/validar_formato_saimo.py canais docs/exemplos/canais
python3 scripts/validar_formato_saimo.py filmes docs/exemplos/filmes
python3 scripts/validar_formato_saimo.py tudo https://seu-site/canais/ https://seu-site/filmes/
```

Ele confere codificação, formato de cada linha, bases do índice, arquivos por letra,
pedaços de série, correspondência de título e ano, e (em endereços web) o CORS. Termina
com código `0` quando não há **erro**; **avisos** não reprovam, mas valem uma olhada.
Só precisa do Python 3, sem instalar nada.

## 8. Erros comuns

| Sintoma no app | Causa provável |
|---|---|
| Nada aparece | Endereço sem `https://`, ou sem `catalogo.txt`/`indice.txt` na pasta; o app mostra vazio em vez de erro |
| Funciona no Mac e não no site/Samsung/LG | Falta `Access-Control-Allow-Origin: *` |
| Canal some | Não tem `fonte:` (é ignorado) ou a `fonte:` não é `http(s)` completa |
| `referer:`/`chave:` não valem | Vieram **antes** da `fonte:` (pertencem à fonte de cima) |
| Filme abre em tela preta | Número de base inexistente, ou base sem `/` no fim, ou `indice.txt` desatualizado em relação às fatias |
| Série abre vazia | Título/ano do `@` diferente do de `series-<LETRA>.txt`, ou pedaço inexistente |
| Filme não aparece na busca | Falta em `busca.txt`, ou está na letra errada |
| Rádios não atualizam | Menos de 10 rádios válidas no arquivo |
| Acentos quebrados | O arquivo não está em UTF-8 |
| Mudei e nada mudou | Cache (no Mac: filmes até 3 h, destaques 15 min). Feche e abra o app; se persistir, use a opção de limpar cache dos Ajustes |

Dúvidas ou um caso que o formato não cobre? Abra uma *issue* em
<https://github.com/SaimoTV/SaimoPlayer/issues>.
