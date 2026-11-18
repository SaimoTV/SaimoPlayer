#!/usr/bin/env python3
"""Referência da classificação de itens de listas M3U (docs/listas-m3u.md).

    python3 scripts/classificar_m3u.py lista.m3u            # resumo
    python3 scripts/classificar_m3u.py lista.m3u --json     # um item por linha (JSON)

Os apps implementam a mesma regra; o gabarito docs/exemplos/listas/ sai daqui.
Sem dependências: só a biblioteca padrão.
"""
import json
import sys
import unicodedata

VIDEO = {"mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp", "divx", "ogv", "vob"}
TIPO_CANAL = {"live", "channel", "tv", "radio"}
TIPO_FILME = {"movie", "movies", "vod", "film", "filme"}
TIPO_SERIE = {"series", "serie", "tvshow", "show", "episode"}
SEG_FILME = {"movie", "movies", "vod", "filmes"}
SEG_SERIE = {"series", "serie"}
PALAVRAS_ACERVO = {"filme", "filmes", "movie", "movies", "vod", "serie", "series", "novela", "novelas",
                   "anime", "animes", "dorama", "doramas", "temporada", "temporadas"}
SEPARADORES = " -:|._([–—\t"


def sem_acento(t):
    return "".join(c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn")


def dobrar(t):
    """Minúsculas sem acento, um caractere por caractere do original."""
    saida = []
    for c in t:
        d = sem_acento(c).lower()
        saida.append(d[0] if len(d) == 1 else (d[:1] or c))
    return "".join(saida)


def palavras(t):
    atual, todas = "", []
    for c in t:
        if c.isalnum():
            atual += c
        else:
            if atual:
                todas.append(atual)
            atual = ""
    if atual:
        todas.append(atual)
    return todas


def inicio_de_palavra(n, i):
    return i == 0 or not n[i - 1].isalnum()


def ler_digitos(n, j, maximo):
    k = j
    while k < len(n) and n[k].isdigit() and k - j < maximo:
        k += 1
    if k == j or (k < len(n) and n[k].isdigit()):
        return None, j
    return int(n[j:k]), k


def pular(n, j, chars):
    while j < len(n) and n[j] in chars:
        j += 1
    return j


PALAVRAS_EP = ("episodio", "episode", "capitulo", "cap", "ep")


def palavra_de_episodio(n, j):
    """Em n[j:], uma palavra de episódio seguida de . ou espaço(s) e dígitos."""
    for p in PALAVRAS_EP:
        if n.startswith(p, j):
            k = j + len(p)
            if k < len(n) and n[k].isalpha():
                continue
            k = pular(n, k, ".")
            k = pular(n, k, " ")
            e, k2 = ler_digitos(n, k, 4)
            if e is not None:
                return e, k2
    return None, j


def marca(nome):
    """(temporada, episodio, inicio, forte) ou None.

    Em três passadas, nesta ordem: S01E02/T01E02 no nome inteiro; depois
    "Temporada N ... Episódio M"; depois 1x02 (nunca no começo do nome:
    "4x4 Sob Medida", "4x100" são títulos). A fraca só sem nenhuma forte.
    """
    n = dobrar(nome)
    for i, c in enumerate(n):
        if not inicio_de_palavra(n, i) or c not in "st":
            continue
        t, j = ler_digitos(n, i + 1, 3)
        if t is None:
            continue
        j = pular(n, j, " ._-")
        if j < len(n) and (n[j] == "e" or (c == "s" and n[j] == "x")):
            j += 1
            if j < len(n) and n[j] == "p":
                j += 1
            j = pular(n, j, " .")
            e, _ = ler_digitos(n, j, 4)
            if e is not None:
                return t, e, i, True
    for i in range(len(n)):
        if not inicio_de_palavra(n, i):
            continue
        for p in ("temporada", "season"):
            if n.startswith(p, i):
                j = pular(n, i + len(p), " ")
                t, j = ler_digitos(n, j, 3)
                if t is not None:
                    for k in range(j, min(j + 13, len(n))):
                        if inicio_de_palavra(n, k):
                            e, _ = palavra_de_episodio(n, k)
                            if e is not None:
                                return t, e, i, True
    for i, c in enumerate(n):
        if i == 0 or not inicio_de_palavra(n, i) or not c.isdigit():
            continue
        t, j = ler_digitos_ate(n, i, 2, "x")
        if t is not None and j < len(n) and n[j] == "x":
            e, k = ler_digitos(n, j + 1, 3)
            if e is not None and (k == len(n) or not n[k].isalnum()):
                return t, e, i, True
    for i in range(len(n)):
        if inicio_de_palavra(n, i):
            e, _ = palavra_de_episodio(n, i)
            if e is not None:
                return 1, e, i, False
    return None


def ler_digitos_ate(n, j, maximo, seguinte):
    """Dígitos (1..maximo) seguidos exatamente do caractere `seguinte`."""
    k = j
    while k < len(n) and n[k].isdigit():
        k += 1
    if k == j or k - j > maximo or k >= len(n) or n[k] != seguinte:
        return None, j
    return int(n[j:k]), k


def atributo(linha, nome):
    procurado = nome + '="'
    de = 0
    while True:
        i = linha.find(procurado, de)
        if i < 0:
            return None
        if i == 0 or linha[i - 1].isspace() or linha[i - 1] == ":":
            fim = linha.find('"', i + len(procurado))
            if fim >= 0:
                return linha[i + len(procurado):fim].strip()
        de = i + len(procurado)


def nome_exibido(linha):
    dentro = False
    for i, c in enumerate(linha):
        if c == '"':
            dentro = not dentro
        elif c == "," and not dentro:
            return linha[i + 1:].strip()
    return ""


def caminho(url):
    u = url.split("#", 1)[0].split("?", 1)[0]
    if "://" in u:
        u = u.split("://", 1)[1]
        u = u.split("/", 1)[1] if "/" in u else ""
    return [s for s in u.lower().split("/") if s]


def grupo_de_acervo(grupo):
    g = dobrar(grupo or "")
    ws = set(palavras(g))
    if not ws & PALAVRAS_ACERVO:
        return False
    if "24h" in g or "24 horas" in g or "24/7" in g or "ao vivo" in g:
        return False
    return not ({"canal", "canais", "live"} & ws)


def ano_no_fim(nome):
    t = nome.rstrip()
    return len(t) >= 6 and t[-1] == ")" and t[-6] == "(" and t[-5:-1].isdigit() and t[-5:-3] in ("19", "20")


def tipo(url, nome, grupo, declarado):
    """'canal', 'filme' ou 'episodio' (com a marca, quando houver)."""
    m = marca(nome)
    # Arquivo de vídeo (.mp4, .mkv, .avi...) nunca é canal, mesmo que a lista
    # declare "live" ou o endereço tenha /live/: canal é .m3u8, .ts, .mpd, .txt
    # ou endereço sem extensão.
    segs0 = caminho(url)
    if segs0 and "." in segs0[-1] and segs0[-1].rsplit(".", 1)[1] in VIDEO:
        return ("episodio", m) if m else ("filme", None)
    d = (declarado or "").strip().lower()
    acervo = None
    if d in TIPO_CANAL:
        return "canal", None
    if d in TIPO_FILME or d in TIPO_SERIE:
        acervo = d
    if acervo is None:
        segs = caminho(url)
        for s in segs[:-1]:
            if s in SEG_FILME:
                acervo = "movie"
                break
            if s in SEG_SERIE:
                acervo = "series"
                break
            if s == "live":
                return "canal", None
        # Canal Xtream sem prefixo: /usuario/senha/123(.ts|.m3u8).
        if acervo is None and len(segs) == 3:
            num, _, ext = segs[2].partition(".")
            if num.isdigit() and ext in ("", "ts", "m3u8"):
                return "canal", None
    if acervo is None and caminho(url):
        ultimo = caminho(url)[-1]
        if "." in ultimo and ultimo.rsplit(".", 1)[1] in VIDEO:
            acervo = "video"
    if acervo is not None:
        return ("episodio", m) if m else ("filme", None)
    if grupo_de_acervo(grupo):
        if m and m[3]:
            return "episodio", m
        if ano_no_fim(limpar(nome)[0]):
            return "filme", None
    return "canal", None


# --- títulos -------------------------------------------------------------

def resolucao(t):
    i = 0
    while i < len(t):
        if t[i].isdigit():
            ini = i
            while i < len(t) and t[i].isdigit():
                i += 1
            if i - ini >= 3 and i < len(t) and t[i] in "pPiI":
                return True
        else:
            i += 1
    return False


def tem_palavra(t, p):
    de = 0
    while True:
        i = t.find(p, de)
        if i < 0:
            return False
        antes = i == 0 or not (t[i - 1].isalnum() or t[i - 1] == "_")
        f = i + len(p)
        depois = f >= len(t) or not (t[f].isalnum() or t[f] == "_")
        if antes and depois:
            return True
        de = i + 1


def tag_ruim(conteudo):
    t = conteudo.lower()
    return (resolucao(t) or "not 24/7" in t or "geoblocked" in t or "geo-blocked" in t or "backup" in t
            or "vertical" in t or tem_palavra(t, "sd") or tem_palavra(t, "hd") or "fhd" in t
            or tem_palavra(t, "4k"))


TAGS_LEG = {"l", "leg", "legendado", "legendada"}
TAGS_DUB = {"d", "dub", "dublado", "dublada", "nac", "nacional"}


def limpar(nome):
    """Tira do fim tags de qualidade e de versão; devolve (nome, versao ou None)."""
    versao = None
    nome = nome.strip()
    while True:
        t = nome.rstrip()
        if t and t[-1] in ")]":
            fecha = t[-1]
            abre = "(" if fecha == ")" else "["
            pos = t.rfind(abre)
            if pos >= 0:
                conteudo = t[pos + 1:-1].strip()
                c = dobrar(conteudo)
                if c in TAGS_LEG:
                    versao = versao or "leg"
                    nome = t[:pos]
                    continue
                if c in TAGS_DUB:
                    versao = versao or "dub"
                    nome = t[:pos]
                    continue
                if tag_ruim(conteudo):
                    nome = t[:pos]
                    continue
        ws = t.rsplit(" ", 1)
        if len(ws) == 2 and dobrar(ws[1]) in ("leg", "legendado", "legendada"):
            versao = versao or "leg"
            nome = ws[0]
            continue
        break
    # Tags de versão no meio ("Filme [L] (2020)").
    for abre, fecha in (("[", "]"), ("(", ")")):
        de = 0
        while True:
            i = nome.find(abre, de)
            if i < 0:
                break
            f = nome.find(fecha, i + 1)
            if f < 0:
                break
            c = dobrar(nome[i + 1:f].strip())
            if c in TAGS_LEG or c in TAGS_DUB:
                versao = versao or ("leg" if c in TAGS_LEG else "dub")
                nome = (nome[:i].rstrip() + " " + nome[f + 1:].lstrip()).strip()
                de = i
            else:
                de = f + 1
    return " ".join(nome.split()), versao


def ano_repetido(nome):
    """'Filme (2025) (2025)' vira 'Filme (2025)'."""
    while True:
        t = nome.rstrip()
        if ano_no_fim(t) and ano_no_fim(t[:-6].rstrip()) and t[-5:-1] == t[:-6].rstrip()[-5:-1]:
            nome = t[:-6].rstrip()
            continue
        return t


def sem_extensao(nome):
    """'Filme.avi' vira 'Filme' (nome de arquivo usado como título)."""
    t = nome.strip()
    if "." in t and t.rsplit(".", 1)[1].lower() in VIDEO:
        return t.rsplit(".", 1)[0].strip()
    return t


def titulo_do_filme(nome, grupo):
    t, versao = limpar(sem_extensao(nome))
    t = ano_repetido(t)
    if versao is None:
        versao = "leg" if "legendad" in dobrar(grupo or "") else "dub"
    ano = t[-5:-1] if ano_no_fim(t) else ""
    return t, ano, versao


def titulo_da_serie(nome, inicio, grupo):
    t, versao = limpar(nome[:inicio].rstrip(SEPARADORES))
    t = t.rstrip(SEPARADORES).strip()
    # Tags de versão depois da marca ("Série S01E01 [L]").
    versao = versao or limpar(nome[inicio:])[1]
    t = ano_repetido(t)
    ano = ""
    if ano_no_fim(t):
        ano = t[-5:-1]
        t = t[:-6].rstrip(SEPARADORES).strip()
    if not t:
        t = (grupo or "").strip() or "Série"
    if versao is None:
        versao = "leg" if "legendad" in dobrar(grupo or "") else "dub"
    return t, ano, versao


def itens(texto):
    texto = texto.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")
    pend = None
    extgrp = None
    for bruta in texto.split("\n"):
        linha = bruta.strip()
        if not linha or linha[:7].upper() == "#EXTM3U":
            continue
        if linha.startswith("#EXTINF"):
            pend = linha
            extgrp = None
            continue
        if linha.startswith("#EXTGRP:"):
            extgrp = linha[8:].strip()
            continue
        if linha.startswith("#"):
            continue
        url = linha.split("|", 1)[0].strip() if "|" in linha and "=" in linha.split("|", 1)[1] else linha
        if not url.lower().startswith(("http://", "https://")):
            pend = None
            continue
        p = pend or ""
        pend = None
        nome = nome_exibido(p) or atributo(p, "tvg-name") or atributo(p, "tvg-id") or ""
        grupo = atributo(p, "group-title") or extgrp or ""
        if ";" in grupo:
            grupo = grupo.split(";")[0].strip()
        declarado = atributo(p, "tvg-type") or atributo(p, "type") or atributo(p, "media-type")
        k, m = tipo(url, nome, grupo, declarado)
        item = {"tipo": k, "nome": nome}
        if k == "filme":
            item["titulo"], item["ano"], item["versao"] = titulo_do_filme(nome, grupo)
        elif k == "episodio":
            item["titulo"], item["ano"], item["versao"] = titulo_da_serie(nome, m[2], grupo)
            item["temporada"], item["episodio"] = m[0], m[1]
        yield item


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        texto = f.read()
    if "--json" in sys.argv:
        for item in itens(texto):
            print(json.dumps(item, ensure_ascii=False))
        return 0
    contagem = {}
    series = set()
    filmes = set()
    for item in itens(texto):
        contagem[item["tipo"]] = contagem.get(item["tipo"], 0) + 1
        if item["tipo"] == "episodio":
            series.add((item["titulo"], item["ano"]))
        elif item["tipo"] == "filme":
            filmes.add(item["titulo"])
    print(contagem, "| filmes distintos:", len(filmes), "| séries distintas:", len(series))
    return 0


if __name__ == "__main__":
    sys.exit(main())
