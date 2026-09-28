"""
Registro en Supabase llamando a la función RPC registrar_boleto_rifa por la
API REST, con la clave SECRETA (solo vive en el servidor).

Se usa `requests` directamente en lugar del paquete supabase para tener menos
dependencias; es la misma petición que hace ese paquete.
"""

import logging

import requests

log = logging.getLogger("servicio_rifa.bd")


class BDNoDisponible(Exception):
    """No se pudo completar la llamada a Supabase (red o error inesperado)."""


class ClienteSupabase:
    def __init__(self, url: str, clave_secreta: str, sesion=None, timeout=15):
        if not (url and clave_secreta):
            raise ValueError("Faltan SUPABASE_URL o SUPABASE_SECRET_KEY en la configuración")
        self._endpoint = url.rstrip("/") + "/rest/v1/rpc/registrar_boleto_rifa"
        self._headers = {"apikey": clave_secreta,
                         "Authorization": f"Bearer {clave_secreta}",
                         "Content-Type": "application/json"}
        self._http = sesion or requests.Session()
        self._timeout = timeout

    def __repr__(self):  # nunca mostrar la clave en un log
        return f"ClienteSupabase(endpoint={self._endpoint!r})"

    def registrar_boleto(self, *, txca, nombre, apellido_paterno, apellido_materno,
                         telefono, clave_catastral, propietario, direccion) -> dict:
        """Devuelve {'success': bool, 'message': str} tal como lo responde la función."""
        params = {
            "p_numero_transaccion": txca,
            "p_nombre_pagador": nombre,
            "p_apellido_paterno": apellido_paterno,
            "p_apellido_materno": apellido_materno,   # None si no tiene
            "p_telefono_pagador": telefono,
            "p_clave_catastral": clave_catastral,
            "p_propietario_registrado": propietario,
            "p_direccion_predio": direccion,
        }
        try:
            r = self._http.post(self._endpoint, json=params, headers=self._headers,
                                timeout=self._timeout)
        except requests.RequestException as e:
            raise BDNoDisponible(f"Sin conexión con Supabase: {type(e).__name__}") from e
        if r.status_code != 200:
            # No se incluye el cuerpo completo: puede traer detalles internos
            raise BDNoDisponible(f"Supabase respondió HTTP {r.status_code}")
        try:
            datos = r.json()
            return {"success": bool(datos["success"]), "message": str(datos["message"])}
        except (ValueError, KeyError, TypeError) as e:
            raise BDNoDisponible("Respuesta inesperada de registrar_boleto_rifa") from e
