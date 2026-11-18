# Listas M3U e Xtream: canal, filme ou episódio

Contrato comum a todos os apps (Mac, Windows/Linux, TV Box, celular, site,
Samsung/LG e Roku). Uma lista M3U, ou uma conta Xtream lida pelo M3U dela
(`get.php?username=…&password=…&type=m3u_plus`), mistura canais ao vivo, filmes e
episódios de séries. Cada item é classificado pelas regras abaixo, **nesta ordem**;
a primeira que decide vale.

**Antes de tudo:** endereço de **arquivo de vídeo** (`mp4 mkv avi mov wmv flv webm m4v mpg mpeg
3gp divx ogv vob`) **nunca é canal**, mesmo que a lista declare `live` ou o caminho tenha `/live/`:
é filme (ou episódio, com marca de episódio). Canal ao vivo é `.m3u8`, `.ts`, `.mpd`, `.txt` ou
endereço sem extensão.

Os canais vão para o Ao vivo (seção "Minhas listas", como sempre). Filmes e séries
vão para Filmes e séries, junto do acervo do Saimo: o app monta com eles um acervo
no **formato Saimo** (`docs/formato-saimo.md`, item 5) guardado no aparelho, um por
lista, e lê esse acervo como lê o publicado.

## 1. O tipo declarado

Atributo `tvg-type`, `type` ou `media-type` do `#EXTINF` (sem diferenciar caixa):

| Valor | Tipo |
|---|---|
| `live`, `channel`, `tv`, `radio` | canal |
| `movie`, `movies`, `vod`, `film`, `filme` | filme (episódio se o nome tiver marca de episódio) |
| `series`, `serie`, `tvshow`, `show`, `episode` | episódio (filme se o nome não tiver marca de episódio) |

## 2. O caminho do endereço

Do endereço, sem esquema, servidor, `?consulta` e `#fragmento`, em minúsculas,
separado por `/`. Se algum **segmento** (não o último) for:

| Segmento | Tipo |
|---|---|
| `movie`, `movies`, `vod`, `filmes` | filme (episódio se o nome tiver marca de episódio) |
| `series`, `serie` | episódio (filme se o nome não tiver marca de episódio) |
| `live` | canal |

É o padrão Xtream: `/movie/U/P/123.mp4`, `/series/U/P/456.mkv`, `/live/U/P/7.ts`.
O canal Xtream sem prefixo também é canal: caminho de **exatamente 3** segmentos
cujo último é só dígitos, com `.ts`, `.m3u8` ou sem extensão (`/U/P/7.ts`).

## 3. A extensão do arquivo

Extensão do último segmento, em minúsculas:

- **vídeo em arquivo**: `mp4 mkv avi mov wmv flv webm m4v mpg mpeg 3gp divx ogv vob`
  - episódio se o nome tiver marca de episódio, senão filme;
- qualquer outra (`m3u8 ts mpd php`…, ou sem extensão): vai para a regra 4.

## 4. O grupo, para o que é transmissão

Grupo (`group-title`, ou `#EXTGRP`) normalizado: minúsculas, sem acento.

- **Grupo de acervo**: tem uma das palavras `filme filmes movie movies vod serie
  series novela novelas anime animes dorama doramas temporada temporadas` **e não**
  tem `24h`, `24 horas`, `24/7`, `ao vivo`, `canal`, `canais`, `live`.
- Grupo de acervo **e** marca de episódio no nome: episódio.
- Grupo de acervo **e** ano `(19xx)`/`(20xx)` no fim do nome (depois de tirar as tags de
  qualidade e de versão): filme.
- Todo o resto: **canal**.

## Marca de episódio

Procurada no nome sem acento e em minúsculas, só no começo de palavra (antes dela
nada ou um caractere que não é letra nem número):

| Forte (procuradas nesta ordem, cada uma no nome inteiro) | Exemplo | Temporada, episódio |
|---|---|---|
| `s` + 1–3 dígitos + (espaço/`.`/`_`/`-`)* + `e`/`x` + `p`? + (espaço/`.`)* + 1–4 dígitos | `S01E02`, `s1 e2`, `S01.E02`, `S1x02` | 1, 2 |
| `t` + 1–3 dígitos + (espaço/`.`/`_`/`-`)* + `e` + `p`? + (espaço/`.`)* + 1–4 dígitos | `T01E02`, `T1 EP2` | 1, 2 |
| 1–2 dígitos + `x` + 1–3 dígitos, **nunca no começo do nome** | `Friends 1x02` (não pega `1920x1080`, nem `4x4 Sob Medida`) | 1, 2 |
| `temporada`/`season` + espaços + dígitos, e em até 12 caracteres depois `episodio`/`episode`/`ep`/`capitulo`/`cap` + `.`? + espaços + dígitos | `Temporada 2 Episódio 5` | 2, 5 |

Em todos, depois dos dígitos do episódio não pode vir outro dígito. Assim `4X4 Sob Medida
S01E01` é a série "4X4 Sob Medida", e `4x100: Correndo por um Sonho` é um título, não um episódio.

| Fraca (só se não houver forte) | Exemplo | Temporada, episódio |
|---|---|---|
| `episodio`/`episode`/`ep`/`capitulo`/`cap` + `.`? + espaços + 1–4 dígitos | `Ep 12`, `Capítulo 40` | 1, 12 |

A marca fraca só conta quando a regra já disse "acervo" (tipo declarado, caminho
ou extensão de vídeo); na regra 4 só a forte conta.

## O nome do título

- **Série:** o texto **antes** da marca, sem os separadores do fim
  (` - : | . _ ( [ – —` e espaços). Vazio: o grupo; sem grupo, "Série".
  Um `(ano)` no fim vira o ano da série e sai do título. Tags de versão saem (abaixo).
- **Filme:** o nome inteiro, sem extensão de vídeo no fim (`Filme.avi`), sem as tags de qualidade do fim (as mesmas que o leitor
  de canais tira: `(720p)`, `[HD]`, `[4K]`…) e sem as tags de versão. Um ano
  repetido (`Filme (2025) (2025)`) fica uma vez só. O ano fica no título, como no
  acervo do Saimo (`Filme (2025)`).
- **Versão:** `leg` se o nome tem `[L]`, `(L)`, `[LEG]`, `(LEG)`, `[Legendado]`,
  `(Legendado)`, ou termina em ` LEG`/` Legendado`; ou se o grupo tem `legendad`.
  Senão `dub`. As tags saem do título.
- Títulos com o mesmo nome (mesma chave: minúsculas, sem acento, só letras e
  números) juntam: filmes viram um título com as versões; episódios iguais
  (mesma temporada, número e versão) viram fontes reserva, na ordem da lista.

## O acervo gerado

No formato Saimo, sem `base:` (todas as fontes são endereços completos):
`indice.txt`, `filmes-<L>.txt`, `series-<L>.txt`, `series-<L>-<N>.txt` (pedaços
de até ~100 KB), `busca.txt`. A letra segue o item 5.1 do formato. Conteúdo
adulto (mesma regra dos canais restritos) não entra no acervo da lista.

Capas e gêneros vão num `fichas.txt` (`capa: ` vazio, endereços completos): a capa é
o `tvg-logo` do primeiro item do título; os gêneros são os grupos (`group-title`) por
onde o título passou, sem os símbolos do começo (`# Drama` vira `Drama`). Uma imagem
usada por **mais de 3 títulos diferentes** é a genérica do provedor e é ignorada
(o título fica sem capa, em vez de com a capa errada). Canais usam o `tvg-logo` como
logo, como sempre.

No Perfil Kids os títulos das listas não aparecem (não têm classificação).

## Gabarito

`docs/exemplos/listas/classificar.m3u` e `classificar.esperado.json`: cada app tem
um teste que lê o `.m3u` e confere tipo, título, ano, temporada, episódio e versão
de cada item com o `.json`.
