"""
Servicio interno de la Rifa Predial.

Corre en el servidor municipal (junto a la versión web del formulario) y es
la ÚNICA pieza que habla con el SRM y con Supabase. El navegador solo le
envía lo que captura el ciudadano.

Endpoints (JSON):
  POST /api/validar    {txca, fecha_pago}
      -> {"ok": true, "direccion": "..."}   para el modal de confirmación
  POST /api/registrar  {txca, fecha_pago, nombre, apellido_paterno,
                        apellido_materno?, telefono}
      -> {"ok": true, "mensaje": "...", "boleto": {"txca", "nombre"}}
  GET  /api/salud      -> {"ok": true}   (para monitoreo)

Errores: {"ok": false, "mensaje": "<texto para mostrar al ciudadano>"} con
HTTP 400 (datos inválidos), 422 (rechazo de negocio), 429 (demasiados
intentos) o 503 (SRM o base de datos sin respuesta).
"""

import logging
import os
import re
from datetime import date

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix

from bd import BDNoDisponible, ClienteSupabase
from limites import LimiteIntentos
from srm import ClienteSRM, SRMNoDisponible, TransaccionRechazada

log = logging.getLogger("servicio_rifa")

# ---------------------------------------------------------------- mensajes
# Mismo mensaje si la transacción no existe, no es predial, está fuera de
# periodo O la fecha no coincide: así nadie puede averiguar qué folios existen.
MSG_NO_ENCONTRADO = ("No encontramos un pago de predial vigente con ese número de "
                     "transacción y fecha de pago. Revisa los datos de tu recibo.")
MSG_PERSONA_MORAL = "El sorteo es exclusivo para personas físicas."
MSG_LIMITE = "Demasiados intentos. Espera unos minutos y vuelve a intentarlo."
MSG_NO_DISPONIBLE = "El servicio no está disponible en este momento. Intenta de nuevo más tarde."

# ------------------------------------------------------------- validación
# re.ASCII: sin él, \d acepta cualquier dígito Unicode (１２３, ١٢٣...) y el
# mismo teléfono escrito con otros dígitos esquivaría el límite de boletos.
RE_TXCA = re.compile(r"^\d{4}-\d{1,10}$", re.ASCII)  # la API acepta ^\d{4}-\d+$
RE_TELEFONO = re.compile(r"^\d{10}$", re.ASCII)
RE_NOMBRE = re.compile(r"^[A-ZÁÉÍÓÚÜÑ]+( [A-ZÁÉÍÓÚÜÑ]+)*$")
LARGO_MAX_NOMBRE = 60


class DatosInvalidos(Exception):
    pass


def _texto(datos, campo, obligatorio=True):
    valor = datos.get(campo)
    if valor is None:
        valor = ""
    if not isinstance(valor, str):
        raise DatosInvalidos(f"El campo {campo} no es válido.")
    valor = " ".join(valor.split())
    if obligatorio and not valor:
        raise DatosInvalidos(f"El campo {campo} es obligatorio.")
    return valor


def _nombre(datos, campo, obligatorio=True, etiqueta=None):
    valor = _texto(datos, campo, obligatorio).upper()
    if not valor:
        return None
    if len(valor) > LARGO_MAX_NOMBRE or not RE_NOMBRE.match(valor):
        raise DatosInvalidos(f"{etiqueta or campo} solo puede contener letras y espacios.")
    return valor


def _cuerpo():
    """El JSON de la petición, que debe ser un objeto. Sin cuerpo (o sin
    JSON válido) se trata como vacío: cada campo avisa que es obligatorio."""
    datos = request.get_json(silent=True)
    if datos is None:
        return {}
    if not isinstance(datos, dict):
        raise DatosInvalidos("La petición no tiene el formato correcto.")
    return datos


def _txca_y_fecha(datos):
    txca = _texto(datos, "txca")
    if not RE_TXCA.match(txca):
        raise DatosInvalidos("El número de transacción no tiene el formato correcto.")
    try:
        fecha = date.fromisoformat(_texto(datos, "fecha_pago"))
    except ValueError:
        raise DatosInvalidos("La fecha de pago no es válida.") from None
    return txca, fecha


# ------------------------------------------------------------------ la app
def crear_app(srm=None, bd=None, limite=None, config=None):
    cfg = dict(os.environ)
    cfg.update(config or {})

    app = Flask(__name__)
    app.json.ensure_ascii = False  # acentos legibles en las respuestas

    # Detrás del proxy del servidor, la IP real del ciudadano viene en
    # X-Forwarded-For. Sin esto, TODAS las peticiones parecerían venir del
    # proxy (red interna) y el límite de intentos no serviría.
    proxies = int(cfg.get("NUMERO_PROXIES", "0"))
    if proxies:
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=proxies)

    srm = srm or ClienteSRM(cfg.get("SRM_URL"), cfg.get("SRM_TOKEN"), cfg.get("SRM_SALT"))
    bd = bd or ClienteSupabase(cfg.get("SUPABASE_URL"), cfg.get("SUPABASE_SECRET_KEY"))
    limite = limite or LimiteIntentos(
        maximo=int(cfg.get("LIMITE_INTENTOS", "15")),
        ventana_segundos=int(cfg.get("LIMITE_VENTANA_SEGUNDOS", "600")),
        redes_exentas=cfg.get("REDES_INTERNAS", "").split(","),
    )
    origenes = {o.strip() for o in cfg.get("ORIGENES_PERMITIDOS", "").split(",") if o.strip()}

    def error(mensaje, http):
        return jsonify(ok=False, mensaje=mensaje), http

    def verificar_pago(txca, fecha):
        """Consulta el SRM y aplica las reglas del sorteo. Devuelve el Predio."""
        try:
            predio = srm.consultar(txca)
        except TransaccionRechazada as e:
            log.info("txca=%s rechazada por el SRM [%s]", txca, e.codigo)
            raise _Rechazo(MSG_NO_ENCONTRADO)
        if predio.fecha_pago != fecha:
            log.info("txca=%s: la fecha de pago no coincide", txca)
            raise _Rechazo(MSG_NO_ENCONTRADO)
        if predio.tipo_persona != "FISICA":
            log.info("txca=%s: persona %s", txca, predio.tipo_persona)
            raise _Rechazo(MSG_PERSONA_MORAL)
        return predio

    @app.before_request
    def controlar_acceso():
        if request.path == "/api/salud" or request.method == "OPTIONS":
            return None
        origen = request.headers.get("Origin")
        if origenes and origen and origen not in origenes:
            return error("Origen no permitido.", 403)
        if not limite.permitir(request.remote_addr or ""):
            log.warning("Límite de intentos alcanzado por %s", request.remote_addr)
            return error(MSG_LIMITE, 429)
        return None

    @app.after_request
    def cabeceras(resp):
        origen = request.headers.get("Origin")
        if origen and origen in origenes:
            resp.headers["Access-Control-Allow-Origin"] = origen
            resp.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
            resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
            resp.headers["Vary"] = "Origin"
        resp.headers["Cache-Control"] = "no-store"
        return resp

    @app.errorhandler(DatosInvalidos)
    def _datos_invalidos(e):
        return error(str(e), 400)

    @app.errorhandler(_Rechazo)
    def _rechazo(e):
        return error(e.mensaje, 422)

    @app.errorhandler(SRMNoDisponible)
    def _srm_caido(e):
        log.error("SRM no disponible: %s", e)
        return error(MSG_NO_DISPONIBLE, 503)

    @app.errorhandler(BDNoDisponible)
    def _bd_caida(e):
        log.error("Supabase no disponible: %s", e)
        return error(MSG_NO_DISPONIBLE, 503)

    @app.errorhandler(Exception)
    def _inesperado(e):
        # Red de seguridad: cualquier error no previsto responde JSON (el
        # formulario solo sabe mostrar "mensaje"), nunca la página HTML de Flask.
        if isinstance(e, HTTPException):
            return e  # 404, 405...: los maneja Flask como siempre
        log.exception("Error inesperado en %s", request.path)
        return error(MSG_NO_DISPONIBLE, 500)

    @app.get("/api/salud")
    def salud():
        return jsonify(ok=True)

    @app.post("/api/validar")
    def validar():
        datos = _cuerpo()
        txca, fecha = _txca_y_fecha(datos)
        predio = verificar_pago(txca, fecha)
        # Solo la dirección, para que el ciudadano confirme que es su predio.
        # Nunca el propietario ni la clave catastral.
        return jsonify(ok=True, direccion=predio.domicilio)

    @app.post("/api/registrar")
    def registrar():
        datos = _cuerpo()
        txca, fecha = _txca_y_fecha(datos)
        nombre = _nombre(datos, "nombre", etiqueta="El nombre")
        paterno = _nombre(datos, "apellido_paterno", etiqueta="El apellido paterno")
        materno = _nombre(datos, "apellido_materno", obligatorio=False,
                          etiqueta="El apellido materno")
        telefono = _texto(datos, "telefono")
        if not RE_TELEFONO.match(telefono):
            raise DatosInvalidos("El teléfono debe tener 10 dígitos.")

        # Se vuelve a consultar el SRM: no se confía en que el navegador ya
        # haya validado. Los datos del predio salen de aquí, NUNCA de la petición.
        predio = verificar_pago(txca, fecha)
        resultado = bd.registrar_boleto(
            txca=txca, nombre=nombre, apellido_paterno=paterno,
            apellido_materno=materno, telefono=telefono,
            clave_catastral=predio.clave_catastral, propietario=predio.propietario,
            direccion=predio.domicilio,
        )
        if not resultado["success"]:
            log.info("txca=%s no registrada: %s", txca, resultado["message"])
            return error(resultado["message"], 422)
        log.info("txca=%s registrada", txca)
        nombre_completo = " ".join(p for p in (nombre, paterno, materno) if p)
        return jsonify(ok=True, mensaje=resultado["message"],
                       boleto={"txca": txca, "nombre": nombre_completo})

    return app


class _Rechazo(Exception):
    def __init__(self, mensaje):
        super().__init__(mensaje)
        self.mensaje = mensaje


if __name__ == "__main__":
    # Solo para pruebas locales. En el servidor usar waitress (ver README).
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    crear_app().run(host="127.0.0.1", port=int(os.environ.get("PUERTO", "8080")))
