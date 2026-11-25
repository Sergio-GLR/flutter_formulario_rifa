"""
Registro en PostgreSQL llamando a la función registrar_boleto_rifa
(base_datos/esquema.sql), con el rol rifa_servicio, que solo puede ejecutar
esa función.

Antes se llamaba por la API REST de Supabase; desde nov 2026 la base vive en
un PostgreSQL propio (primero local y después en el servidor del municipio).
La función, sus reglas y sus mensajes son los mismos.
"""

import json
import logging
from urllib.parse import urlsplit

import psycopg

log = logging.getLogger("servicio_rifa.bd")

# Si la función no manda mensaje, el ciudadano ve uno de estos (nunca "None")
MSG_EXITO = "Registro completado exitosamente."
MSG_RECHAZO = "No fue posible completar el registro. Revisa tus datos e intenta de nuevo."

# (conectar, consulta) en segundos. Sumado al peor caso del SRM (26 s, ver
# srm.TIMEOUT_SRM) da 39 s, menos que los 45 s que espera el formulario. Si
# alguno sube, revisar que la suma siga cabiendo. La consulta la corta el
# propio Postgres (statement_timeout); la función responde en milisegundos.
TIMEOUT_BD = (5, 8)

SQL_REGISTRAR = "SELECT public.registrar_boleto_rifa(%s, %s, %s, %s, %s, %s, %s, %s)"


class BDNoDisponible(Exception):
    """No se pudo completar la llamada a la base (red, permisos o respuesta inesperada)."""


def _conectar(dsn: str, tiempo_conexion: int, tiempo_consulta: int):
    # Una conexión por registro: el volumen es bajo (un ciudadano registra
    # unos pocos boletos) y así no hay conexiones colgadas que administrar.
    return psycopg.connect(
        dsn,
        autocommit=True,
        connect_timeout=tiempo_conexion,
        options=f"-c statement_timeout={tiempo_consulta * 1000}",
    )


class ClientePostgres:
    def __init__(self, dsn: str, conectar=None, tiempo_conexion: int = TIMEOUT_BD[0],
                 tiempo_consulta: int = TIMEOUT_BD[1]):
        if not dsn:
            raise ValueError("Falta DATABASE_URL en la configuración")
        self._dsn = dsn
        self._conectar = conectar or (lambda d: _conectar(d, tiempo_conexion, tiempo_consulta))

    def __repr__(self):  # nunca mostrar la contraseña en un log
        partes = urlsplit(self._dsn)
        return f"ClientePostgres(host={partes.hostname!r}, base={partes.path.lstrip('/')!r})"

    def registrar_boleto(self, *, txca, nombre, apellido_paterno, apellido_materno,
                         telefono, clave_catastral, propietario, direccion) -> dict:
        """Devuelve {'success': bool, 'message': str} tal como lo responde la función."""
        params = (txca, nombre, apellido_paterno, apellido_materno, telefono,
                  clave_catastral, propietario, direccion)
        try:
            with self._conectar(self._dsn) as conexion:
                fila = conexion.execute(SQL_REGISTRAR, params).fetchone()
        except psycopg.Error as e:
            # Solo el tipo: el texto de psycopg puede traer usuario, host o
            # detalles internos, y este mensaje llega al log del servidor.
            raise BDNoDisponible(f"Error de PostgreSQL: {type(e).__name__}") from None
        except OSError as e:
            raise BDNoDisponible(f"Sin conexión con PostgreSQL: {type(e).__name__}") from None

        try:
            datos = fila[0]
            if isinstance(datos, str):  # json sin decodificar (otro adaptador)
                datos = json.loads(datos)
            exito = datos["success"]
            mensaje = datos.get("message")
        except (ValueError, KeyError, TypeError, AttributeError, IndexError) as e:
            raise BDNoDisponible("Respuesta inesperada de registrar_boleto_rifa") from e
        # Solo un booleano real cuenta: bool("false") es True en Python y un
        # rechazo se reportaría como registro exitoso.
        if not isinstance(exito, bool):
            raise BDNoDisponible(f"registrar_boleto_rifa devolvió success={type(exito).__name__}")
        if not isinstance(mensaje, str) or not mensaje.strip():
            mensaje = MSG_EXITO if exito else MSG_RECHAZO
        return {"success": exito, "message": mensaje}
