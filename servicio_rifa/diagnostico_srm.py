"""
Diagnóstico de la conexión con el SRM (Pr_sorteo).

Prueba el ambiente TEST y el de PRODUCCIÓN, con la petición tal como la hace
el servicio y con cabeceras de navegador, y muestra qué responde cada uno.
Solo CONSULTA (según la documentación, no crea ni modifica pagos) y nunca
imprime el token, el salt ni la firma.

Uso (desde la carpeta servicio_rifa, en la red municipal):
    python diagnostico_srm.py                  # usa el folio del ejemplo de la documentación
    python diagnostico_srm.py 2026-123456      # u otro folio
"""

import json
import os
import sys
import time

import requests
from dotenv import load_dotenv

from srm import TIMEOUT_SEGUNDOS, firmar

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
TOKEN = os.environ.get("SRM_TOKEN", "")
SALT = os.environ.get("SRM_SALT", "")
URL = os.environ.get("SRM_URL", "")
if not (TOKEN and SALT and URL):
    sys.exit("Falta SRM_URL, SRM_TOKEN o SRM_SALT en el .env")

txca = sys.argv[1] if len(sys.argv) > 1 else "2026-337308"
base = URL.rsplit("/", 1)[0]
firma = firmar(txca, TOKEN, SALT)
cuerpo = {"txca": txca, "signature": firma, "token": TOKEN}

NAVEGADOR = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/129.0 Safari/537.36"),
    "Origin": "http://localhost:5000",
}


def tapar(texto):
    for secreto in (TOKEN, SALT, firma):
        texto = texto.replace(secreto, "***")
    return " ".join(texto.split())


def probar(nombre, url, **kw):
    inicio = time.perf_counter()
    try:
        r = requests.post(url, timeout=TIMEOUT_SEGUNDOS, **kw)
        ms = (time.perf_counter() - inicio) * 1000
        tipo = r.headers.get("Content-Type", "?")
        try:
            datos = r.json()
            if "response" in datos:
                resumen = "✅ response (transacción válida)"
            elif "error" in datos:
                resumen = f"⚠️ error {datos['error'].get('codigo')}: {datos['error'].get('mensaje')}"
            else:
                resumen = f"JSON inesperado: {tapar(json.dumps(datos))[:200]}"
        except ValueError:
            resumen = f"❌ NO es JSON: {tapar(r.text)[:300] or '<respuesta vacía>'}"
        print(f"  {nombre:<32} HTTP {r.status_code}  {ms:5.0f} ms  [{tipo}]\n      {resumen}")
    except requests.RequestException as e:
        print(f"  {nombre:<32} sin respuesta: {type(e).__name__}: {tapar(str(e))[:200]}")


def red():
    """¿A qué IP resuelve el SRM y desde qué IP salimos? Una IP interna
    (10.x, 172.16-31.x, 192.168.x) indica que estamos dentro de la red municipal."""
    import ipaddress
    import socket
    from urllib.parse import urlparse
    host = urlparse(base).hostname
    try:
        ips = sorted({i[4][0] for i in socket.getaddrinfo(host, 443)})
    except OSError as e:
        print(f"  DNS: no se pudo resolver {host}: {e}")
        return
    for ip in ips:
        tipo = "INTERNA (red municipal)" if ipaddress.ip_address(ip).is_private else "PÚBLICA (internet)"
        print(f"  {host} -> {ip}  [{tipo}]")
    try:  # IP local con la que salimos hacia ese servidor (no envía nada)
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect((ips[0], 443))
        print(f"  Tu equipo sale por: {s.getsockname()[0]}")
        s.close()
    except OSError:
        pass


def cabeceras(url):
    """Qué servidor contesta (nginx, IIS, Apache...) y qué dice un GET."""
    try:
        r = requests.get(url, timeout=TIMEOUT_SEGUNDOS)
        interesantes = {k: v for k, v in r.headers.items()
                        if k.lower() in ("server", "x-powered-by", "via", "x-aspnet-version")}
        print(f"  GET -> HTTP {r.status_code}  cabeceras del servidor: {interesantes or 'ninguna'}")
        print(f"      cuerpo: {tapar(r.text)[:200] or '<vacío>'}")
    except requests.RequestException as e:
        print(f"  GET sin respuesta: {type(e).__name__}")


print(f"Folio: {txca}   (firma de 64 caracteres calculada, no se muestra)\n")
print("== Red")
red()
print()
for ambiente, ruta in (("TEST", "Pr_sorteo10"), ("PRODUCCIÓN", "Pr_sorteo")):
    url = f"{base}/{ruta}"
    print(f"== {ambiente}: .../{ruta}")
    probar("como lo hace el servicio", url, json=cuerpo,
           headers={"Accept": "application/json"})
    probar("con cabeceras de navegador", url, data=json.dumps(cuerpo), headers=NAVEGADOR)
    # Firma inválida A PROPÓSITO: si la lógica del SRM corre, debe contestar
    # un JSON con error (la documentación muestra ERROR-07), no un 500.
    probar("firma inválida (control)", url,
           json=dict(cuerpo, signature="0" * 64), headers={"Accept": "application/json"})
    # Variantes de FORMATO: si alguna contesta JSON, el SRM espera otro formato
    probar("como formulario (urlencoded)", url, data=cuerpo,
           headers={"Accept": "application/json"})
    probar("JSON con charset=utf-8", url, data=json.dumps(cuerpo).encode(),
           headers={"Content-Type": "application/json; charset=utf-8",
                    "Accept": "application/json"})
    probar("cuerpo vacío", url, data=b"",
           headers={"Content-Type": "application/json", "Accept": "application/json"})
    # JSON COMPACTO, sin espacios: así lo mandaba el formulario de Flutter
    # (jsonEncode), que sí funcionaba. Python pone espacios por defecto.
    compacto = json.dumps(cuerpo, separators=(",", ":")).encode()
    probar("JSON compacto (como Flutter)", url, data=compacto,
           headers={"Content-Type": "application/json; charset=utf-8",
                    "Accept": "application/json"})
    probar("JSON compacto, firma inválida", url,
           data=json.dumps(dict(cuerpo, signature="0" * 64), separators=(",", ":")).encode(),
           headers={"Content-Type": "application/json; charset=utf-8",
                    "Accept": "application/json"})
    cabeceras(url)
    print()
