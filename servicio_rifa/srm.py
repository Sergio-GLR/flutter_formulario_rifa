"""
Cliente del Web Service Pr_sorteo del Sistema Recaudador Municipal (SRM).

Sigue el contrato de la "Propuesta Técnica: Sorteos — Integración APP-EX":
  * firma = HMAC_SHA256(key = salt en ASCII, message = txca + token), hex minúsculas
  * POST JSON {txca, signature, token}
  * éxito  -> objeto "response";  rechazo -> objeto "error"
  * timeout sugerido 8-15 s; reintentar máximo 1 vez ante error de RED
    (nunca ante un error de negocio)

El token y el salt SOLO viven aquí, en el servidor. Nunca se devuelven al
navegador ni se escriben en los logs.
"""

import hashlib
import json
import hmac
import logging
from dataclasses import dataclass
from datetime import date, datetime

import requests

log = logging.getLogger("servicio_rifa.srm")

TIMEOUT_SEGUNDOS = 12


@dataclass(frozen=True)
class Predio:
    """Lo que devuelve el SRM para una transacción válida."""
    txca: str
    clave_catastral: str
    propietario: str
    domicilio: str
    tipo_persona: str
    fecha_pago: date  # solo el día; la hora no se compara


class TransaccionRechazada(Exception):
    """El SRM respondió con 'error' (formato, firma, tipo de pago, periodo...).
    Es un rechazo de negocio: NO se reintenta."""

    def __init__(self, codigo, mensaje):
        super().__init__(f"{codigo}: {mensaje}")
        self.codigo = codigo
        self.mensaje = mensaje


class SRMNoDisponible(Exception):
    """No se pudo hablar con el SRM (red, timeout, respuesta ilegible)."""


def firmar(txca: str, token: str, salt: str) -> str:
    """HMAC-SHA256 en hex minúsculas, con el salt como texto (no como hex)."""
    return hmac.new(salt.encode("utf-8"), (txca + token).encode("utf-8"),
                    hashlib.sha256).hexdigest()


def _leer_fecha_pago(texto: str) -> date:
    """Formato observado en la documentación: 'DD-MM-YYYY HH:mm:ss'."""
    return datetime.strptime(texto.strip()[:10], "%d-%m-%Y").date()


class ClienteSRM:
    def __init__(self, url: str, token: str, salt: str, sesion=None):
        if not (url and token and salt):
            raise ValueError("Faltan SRM_URL, SRM_TOKEN o SRM_SALT en la configuración")
        self.url = url
        self._token = token
        self._salt = salt
        self._http = sesion or requests.Session()

    def __repr__(self):  # evita que el token o el salt aparezcan en un log por accidente
        return f"ClienteSRM(url={self.url!r})"

    def _fragmento(self, respuesta, firma, largo=300) -> str:
        """Inicio de una respuesta rara del SRM, para el log del servidor (nunca
        para el navegador). Se tapan token, salt y firma por si el SRM los repite."""
        try:
            texto = respuesta.text or ""
        except Exception:
            return "<sin cuerpo legible>"
        for secreto in (self._token, self._salt, firma):
            texto = texto.replace(secreto, "***")
        texto = " ".join(texto.split())
        return (texto[:largo] + "…") if len(texto) > largo else (texto or "<vacío>")

    def consultar(self, txca: str) -> Predio:
        cuerpo = {"txca": txca, "signature": firmar(txca, self._token, self._salt),
                  "token": self._token}
        # JSON COMPACTO (sin espacios), idéntico al que enviaba el formulario de
        # Flutter con jsonEncode. Con los espacios que pone Python por defecto
        # (requests json=), el SRM responde HTTP 500 vacío.
        cuerpo_json = json.dumps(cuerpo, separators=(",", ":")).encode("utf-8")
        ultimo_error = None
        for intento in (1, 2):  # máximo 1 reintento, solo por errores de red
            try:
                r = self._http.post(self.url, data=cuerpo_json, timeout=TIMEOUT_SEGUNDOS,
                                    headers={"Content-Type": "application/json; charset=utf-8",
                                             "Accept": "application/json"})
                datos = r.json()
                break
            except (requests.ConnectionError, requests.Timeout) as e:
                ultimo_error = e
                log.warning("SRM sin respuesta (intento %s de 2) para txca=%s: %s",
                            intento, txca, type(e).__name__)
            except ValueError as e:  # respuesta que no es JSON
                raise SRMNoDisponible(f"Respuesta no JSON del SRM (HTTP {r.status_code}): "
                                      f"{self._fragmento(r, cuerpo['signature'])}") from e
            except requests.RequestException as e:
                # Cualquier otro error de requests (respuesta cortada, mal
                # comprimida, demasiadas redirecciones...). No se reintenta:
                # el SRM sí contestó, pero algo salió mal a medio camino.
                raise SRMNoDisponible(f"Error al leer la respuesta del SRM: "
                                      f"{type(e).__name__}") from e
        else:
            raise SRMNoDisponible("El SRM no respondió tras 2 intentos") from ultimo_error

        if isinstance(datos, dict) and "error" in datos:
            err = datos["error"] or {}
            if not isinstance(err, dict):
                # El contrato dice {"error": {"codigo", "mensaje"}}; otra forma
                # no se puede interpretar como rechazo de negocio.
                raise SRMNoDisponible(f"'error' del SRM con forma desconocida: "
                                      f"{type(err).__name__}")
            raise TransaccionRechazada(err.get("codigo", "?"), err.get("mensaje", ""))

        resp = datos.get("response") if isinstance(datos, dict) else None
        try:
            return Predio(
                txca=resp["txca"],
                clave_catastral=resp["cc"].strip(),
                propietario=resp["propietario"].strip(),
                domicilio=resp["domicilio"].strip(),
                tipo_persona=resp["t_persona"].strip().upper(),
                fecha_pago=_leer_fecha_pago(resp["fecha_pago"]),
            )
        except (TypeError, KeyError, AttributeError, ValueError) as e:
            raise SRMNoDisponible("Estructura de respuesta del SRM desconocida") from e
