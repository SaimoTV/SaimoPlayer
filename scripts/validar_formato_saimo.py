#!/usr/bin/env python3
"""Confere uma lista no formato Saimo antes de colocar o endereço no app.

Uso:
    python3 scripts/validar_formato_saimo.py canais  <pasta-ou-endereço>
    python3 scripts/validar_formato_saimo.py filmes  <pasta-ou-endereço>
    python3 scripts/validar_formato_saimo.py tudo    <pasta-canais> <pasta-filmes>

O alvo pode ser uma pasta do computador ou o endereço publicado
(https://seu-site.pages.dev/). Só usa a biblioteca padrão do Python 3.

Sai com código 0 quando não há ERRO (avisos não reprovam) e 1 quando há.
O formato está descrito em docs/formato-saimo.md.
"""
import os
import re
import sys
import urllib.error
import urllib.request

CATEGORIAS = {
    "TV Aberta", "Filmes e Séries", "Esportes", "Notícias", "Infantil",
    "Documentários", "Pluto TV", "24 Horas", "Variedades", "Músicas", "Adulto",
}
LETRAS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ#")
VERSOES = {"dub", "leg"}

erros: list[str] = []
avisos: list[str] = []


def erro(arq: str, linha: int | None, msg: str) -> None:
    erros.append(f"ERRO   {arq}{':' + str(linha) if linha else ''}  {msg}")


def aviso(arq: str, linha: int | None, msg: str) -> None:
    avisos.append(f"aviso  {arq}{':' + str(linha) if linha else ''}  {msg}")


class Fonte:
    """Lê arquivos de uma pasta ou de um endereço, do mesmo jeito."""

    def __init__(self, alvo: str):
        self.web = alvo.startswith(("http://", "https://"))
        self.alvo = alvo if not self.web or alvo.endswith("/") else alvo + "/"
        if self.web and not alvo.endswith("/"):
            aviso("endereço", None, "o endereço deve terminar com / (o app só acrescenta o nome do arquivo)")

    def ler(self, nome: str) -> str | None:
        try:
            if self.web:
                req = urllib.request.Request(
                    self.alvo + nome.replace("#", "%23"),
                    headers={"User-Agent": "validador-formato-saimo"})
                with urllib.request.urlopen(req, timeout=25) as r:
                    cors = r.headers.get("Access-Control-Allow-Origin")
                    if cors not in ("*",) and not getattr(self, "_avisou_cors", False):
                        self._avisou_cors = True
                        aviso(nome, None, "sem 'Access-Control-Allow-Origin: *': o site e as TVs Samsung/LG "
                                          "não vão conseguir ler (apps nativos leem normalmente)")
                    dados = r.read()
            else:
                with open(os.path.join(self.alvo, nome), "rb") as f:
                    dados = f.read()
        except (urllib.error.URLError, FileNotFoundError, OSError, ValueError):
            return None
        try:
            texto = dados.decode("utf-8")
        except UnicodeDecodeError:
            erro(nome, None, "o arquivo não está em UTF-8")
            texto = dados.decode("utf-8", "replace")
        if texto.startswith("﻿"):
            aviso(nome, None, "tem BOM no início; salve como UTF-8 sem BOM")
        if "\r" in texto:
            aviso(nome, None, "tem quebra de linha do Windows (CRLF); prefira LF")
        return texto


def linhas(texto: str):
    for i, bruta in enumerate(texto.split("\n"), 1):
        yield i, bruta.rstrip("\r")


def url_ok(valor: str) -> bool:
    return bool(re.match(r"^https?://[^\s]+$", valor))


# ---------------------------------------------------------------- canais

def validar_catalogo(src: Fonte, nome: str = "catalogo.txt", obrigatorio: bool = True) -> int:
    texto = src.ler(nome)
    if texto is None:
        if obrigatorio:
            erro(nome, None, "não encontrado")
        return 0
    if texto.lstrip().startswith("#EXTM3U"):
        aviso(nome, None, "é M3U: o Mac e o site leem, mas o Roku só lê o formato 'chave: valor'. "
                          "Para funcionar em todos os apps, use o formato Saimo")
        return texto.count("#EXTINF")
    canais = 0
    nomes: set[str] = set()
    atual = None
    fontes = 0
    ultima_fonte = False

    def fechar(l: int):
        if atual is not None and fontes == 0:
            erro(nome, l, f"o canal '{atual}' não tem nenhuma 'fonte:' e será ignorado")

    for i, l in linhas(texto):
        t = l.strip()
        if not t or t.startswith("#"):
            continue
        if ":" not in t:
            aviso(nome, i, "linha sem 'chave: valor' é ignorada")
            continue
        chave, _, valor = t.partition(":")
        chave, valor = chave.strip().lower(), valor.strip()
        if not valor:
            continue
        if chave == "canal":
            fechar(i)
            atual, fontes, ultima_fonte = valor, 0, False
            canais += 1
            if valor.lower() in nomes:
                aviso(nome, i, f"canal repetido: '{valor}' (junte as fontes em um só)")
            nomes.add(valor.lower())
        elif atual is None:
            erro(nome, i, f"'{chave}:' antes de qualquer 'canal:'")
        elif chave == "logo":
            if not url_ok(valor):
                aviso(nome, i, "logo não é um endereço http(s)")
        elif chave == "categoria":
            if valor not in CATEGORIAS:
                aviso(nome, i, f"categoria '{valor}' não é uma das padrão (vira seção própria no Roku "
                               "e cai na regra do nome nos demais)")
        elif chave == "fonte":
            fontes += 1
            ultima_fonte = True
            if not url_ok(valor):
                erro(nome, i, "fonte precisa ser um endereço http(s) completo")
        elif chave in ("referer", "agente", "chave", "nome", "qualidade"):
            if not ultima_fonte:
                erro(nome, i, f"'{chave}:' precisa vir depois de uma 'fonte:'")
            if chave == "chave" and not re.match(r"^[0-9a-fA-F]{32}:[0-9a-fA-F]{32}$", valor):
                aviso(nome, i, "chave ClearKey deve ser KID:CHAVE, 32 hexadecimais cada")
        else:
            aviso(nome, i, f"chave desconhecida '{chave}' é ignorada")
    fechar(0)
    if canais == 0:
        erro(nome, None, "nenhum canal encontrado")
    return canais


def validar_radios(src: Fonte) -> None:
    texto = src.ler("radios.txt")
    if texto is None:
        aviso("radios.txt", None, "não encontrado (opcional: sem ele a aba Rádios fica vazia)")
        return
    vistos, boas = set(), 0
    for i, l in linhas(texto):
        if not l.strip():
            continue
        p = [x.strip() for x in l.split("|")]
        if len(p) < 2 or not p[0] or not p[1].startswith("http"):
            erro("radios.txt", i, "esperado: nome|endereço[|logo], com endereço começando em http")
            continue
        if p[0] in vistos:
            aviso("radios.txt", i, f"nome repetido '{p[0]}' (o app guarda só a primeira)")
        vistos.add(p[0])
        boas += 1
    if 0 < boas < 10:
        aviso("radios.txt", None, f"só {boas} rádios válidas: os apps ignoram a lista inteira se vierem "
                                  "menos de 10 (o Mac a trata como incompleta)")


def validar_guia(src: Fonte) -> None:
    texto = src.ler("guia.txt")
    if texto is None:
        return
    for i, l in linhas(texto):
        if not l.strip() or l.startswith("#"):
            continue
        c = l.split("\t")
        if len(c) < 3 or c[0] not in ("meuguia", "guiadetv", "alias", "feed", "pluto"):
            erro("guia.txt", i, "esperado: tipo<TAB>nome<TAB>valor (tipos: meuguia, guiadetv, alias, feed, pluto)")


def validar_canais(src: Fonte) -> None:
    n = validar_catalogo(src)
    validar_catalogo(src, "canais.txt", obrigatorio=False)
    validar_catalogo(src, "restritos.txt", obrigatorio=False)
    validar_radios(src)
    validar_guia(src)
    print(f"canais: {n} canal(is) no catalogo.txt")


# ---------------------------------------------------------------- filmes

def letra_do(titulo: str) -> str:
    import unicodedata
    t = unicodedata.normalize("NFKD", titulo).encode("ascii", "ignore").decode().strip()[:1].upper()
    return t if "A" <= t <= "Z" else "#"


def fonte_vod_ok(valor: str, nbases: int) -> bool:
    if valor.startswith("http"):
        return url_ok(valor)
    m = re.match(r"^(\d+):(.+)$", valor)
    return bool(m) and int(m.group(1)) < nbases


def validar_episodios(arq: str, texto: str, nbases: int, titulo: str | None = None) -> int:
    n = 0
    for i, l in linhas(texto):
        if not l.strip() or l.startswith("@"):
            continue
        c = l.split("\t")
        if len(c) < 4:
            erro(arq, i, "episódio: esperado temporada<TAB>episódio<TAB>versão<TAB>fontes")
            continue
        if not (c[0].isdigit() and c[1].isdigit()):
            erro(arq, i, "temporada e episódio devem ser números")
        if c[2] not in VERSOES:
            aviso(arq, i, f"versão '{c[2]}' (use dub ou leg)")
        for f in c[3].split(","):
            if not fonte_vod_ok(f.strip(), nbases):
                erro(arq, i, f"fonte inválida (base fora do índice ou endereço incompleto): {f.strip()[:60]}")
        n += 1
    return n


def validar_filmes(src: Fonte) -> None:
    ind = src.ler("indice.txt")
    if ind is None:
        erro("indice.txt", None, "não encontrado: é o arquivo que dá sentido aos outros")
        return
    bases: list[str] = []
    gavetas: dict[str, tuple[int, int, int]] = {}
    for i, l in linhas(ind):
        if not l.strip() or (l.startswith("#") and not l.startswith("#\t")):
            continue
        if l.startswith("base:"):
            p = l[5:].strip().split(" ", 1)
            if len(p) != 2 or not p[0].isdigit() or not url_ok(p[1]):
                erro("indice.txt", i, "esperado: base: N endereço-completo")
                continue
            if int(p[0]) != len(bases):
                erro("indice.txt", i, f"as bases devem ser numeradas em sequência a partir de 0 (veio {p[0]})")
            if not p[1].endswith("/"):
                aviso("indice.txt", i, "base sem / no fim: o app cola o resto direto nela")
            bases.append(p[1])
            continue
        c = l.split("\t")
        if len(c) < 3 or c[0] not in LETRAS or not (c[1].isdigit() and c[2].isdigit()):
            erro("indice.txt", i, "esperado: letra<TAB>filmes<TAB>séries[<TAB>reservados]")
            continue
        gavetas[c[0]] = (int(c[1]), int(c[2]), int(c[3]) if len(c) > 3 and c[3].isdigit() else 0)
    if not gavetas:
        erro("indice.txt", None, "nenhuma linha de letra encontrada")
    total_f = total_s = 0
    for letra, (nf, ns, _) in sorted(gavetas.items()):
        if nf:
            arq = f"filmes-{letra}.txt"
            t = src.ler(arq)
            if t is None:
                erro(arq, None, f"o índice anuncia {nf} filme(s) nesta letra, mas o arquivo não existe")
            else:
                achados = 0
                for i, l in linhas(t):
                    if not l.strip():
                        continue
                    c = l.split("\t")
                    if len(c) < 2 or not c[0].strip():
                        erro(arq, i, "esperado: título<TAB>versão=fontes[<TAB>versão=fontes]")
                        continue
                    if letra_do(c[0]) != letra:
                        aviso(arq, i, f"'{c[0][:40]}' começa com {letra_do(c[0])}, não {letra}")
                    ok = False
                    for parte in c[1:]:
                        if "=" not in parte:
                            erro(arq, i, "fonte sem 'versão=' (ex.: dub=0:1001)")
                            continue
                        v, _, lista = parte.partition("=")
                        if v not in VERSOES:
                            aviso(arq, i, f"versão '{v}' (use dub ou leg)")
                        for f in lista.split(","):
                            if fonte_vod_ok(f.strip(), len(bases)):
                                ok = True
                            else:
                                erro(arq, i, f"fonte inválida (base fora do índice ou endereço incompleto): {f.strip()[:60]}")
                    if ok:
                        achados += 1
                if achados != nf:
                    aviso(arq, None, f"o índice diz {nf} filme(s), o arquivo tem {achados}")
                total_f += achados
        if ns:
            arq = f"series-{letra}.txt"
            t = src.ler(arq)
            if t is None:
                erro(arq, None, f"o índice anuncia {ns} série(s) nesta letra, mas o arquivo não existe")
                continue
            pedacos: dict[int, list[tuple[str, str, int]]] = {}
            for i, l in linhas(t):
                if not l.strip():
                    continue
                c = l.split("\t")
                if len(c) < 4 or not (c[2].isdigit() and c[3].isdigit()):
                    erro(arq, i, "esperado: título<TAB>ano<TAB>pedaço<TAB>nº de episódios")
                    continue
                pedacos.setdefault(int(c[2]), []).append((c[0], c[1], int(c[3])))
            total_s += sum(len(v) for v in pedacos.values())
            for p, series in sorted(pedacos.items()):
                parq = f"series-{letra}-{p}.txt"
                tp = src.ler(parq)
                if tp is None:
                    erro(parq, None, "pedaço citado em " + arq + " não existe")
                    continue
                cabecalhos = {}
                for i, l in linhas(tp):
                    if l.startswith("@"):
                        h = l[1:].split("\t")
                        cabecalhos[(h[0], h[1] if len(h) > 1 else "")] = i
                for tit, ano, _ in series:
                    if (tit, ano) not in cabecalhos:
                        erro(parq, None, f"falta o bloco '@{tit}' (ano '{ano}'): título e ano devem ser idênticos aos de {arq}")
                validar_episodios(parq, tp, len(bases))
    # opcionais
    for nome, minimo in (("busca.txt", 3), ("destaques.txt", 5), ("fichas.txt", 5), ("detalhes.txt", 6)):
        t = src.ler(nome)
        if t is None:
            aviso(nome, None, "não encontrado (opcional)")
            continue
        for i, l in linhas(t):
            if not l.strip() or l.startswith("#") or l.startswith("capa:") or l.startswith("fila\t"):
                continue
            if len(l.split("\t")) < minimo:
                erro(nome, i, f"esperadas pelo menos {minimo} colunas separadas por TAB")
    if src.ler("redeflix/links-animes.txt") is not None:
        validar_episodios("redeflix/links-animes.txt", src.ler("redeflix/links-animes.txt") or "", len(bases))
    print(f"filmes: {len(bases)} base(s), {len(gavetas)} letra(s), {total_f} filme(s), {total_s} série(s)")


def main() -> int:
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "canais":
        validar_canais(Fonte(a[1]))
    elif len(a) == 2 and a[0] == "filmes":
        validar_filmes(Fonte(a[1]))
    elif len(a) == 3 and a[0] == "tudo":
        validar_canais(Fonte(a[1]))
        validar_filmes(Fonte(a[2]))
    else:
        print(__doc__)
        return 2
    for m in avisos + erros:
        print(m)
    print(f"\n{len(erros)} erro(s), {len(avisos)} aviso(s)")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main())
