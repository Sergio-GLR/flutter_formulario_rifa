"""
Revisión crítica del servicio interno (28 sep 2026).

Cada prueba documenta un defecto o un supuesto frágil encontrado al intentar
romper el servicio. NO se corrigió nada: estas pruebas FALLAN con el código
actual y deben pasar cuando se corrija cada defecto. Correr desde la carpeta
servicio_rifa:

    python -m unittest -v tests.test_revision_critica

Convención (igual que en test/revision_test.dart):
  * clase Falla...    -> defecto confirmado.
  * clase Supuesto... -> el código asume algo que no está garantizado; hay que
                         confirmar con el SRM / Supabase antes de decidir.
"""

import logging
import os
import sys
import unittest

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bd import BDNoDisponible, ClienteSupabase  # noqa: E402
from limites import LimiteIntentos  # noqa: E402
from srm import ClienteSRM, SRMNoDisponible, TransaccionRechazada  # noqa: E402

from tests.test_servicio import (  # noqa: E402
    SALT_FALSO, TOKEN_FALSO, BDFalsa, SRMFalso, _Base, _Resp, _SesionFalla,
    datos_registro, predio)


def setUpModule():
    # Las pruebas provocan errores 500 a propósito; no ensuciar la salida.
    logging.disable(logging.CRITICAL)


def tearDownModule():
    logging.disable(logging.NOTSET)


# ================================================== app.py: cuerpo de la petición
class FallaCuerpoQueNoEsObjeto(_Base):
    """app.py `_texto` hace datos.get(...) sin revisar que el JSON sea un
    objeto. Un cuerpo `[1]`, `"hola"` o `5` truena con AttributeError: HTTP 500
    con la página HTML de Flask en lugar de un 400 con {"ok": false, ...}."""

    def test_json_que_no_es_objeto_responde_400_en_json(self):
        self.armar()
        for ruta in ("/api/validar", "/api/registrar"):
            for crudo in ("[1]", '"hola"', "5", "true"):
                with self.subTest(ruta=ruta, cuerpo=crudo):
                    r = self.cliente.post(ruta, data=crudo, content_type="application/json",
                                          environ_base={"REMOTE_ADDR": "200.1.1.1"})
                    self.assertEqual(r.status_code, 400)
                    self.assertTrue(r.is_json, "Respondió HTML en vez de JSON")
                    self.assertIs(r.json["ok"], False)
        self.assertEqual(self.srm.consultas, [])


# ================================================== app.py: dígitos Unicode
class FallaDigitosUnicode(_Base):
    r"""En Python, `\d` acepta CUALQUIER dígito Unicode (１２３ de ancho
    completo, ١٢٣ arábigos...). RE_TELEFONO y RE_TXCA los dejan pasar: el
    teléfono se guarda en Supabase con caracteres que no son 0-9 (y el límite
    de 5 boletos por teléfono se puede esquivar escribiendo el mismo número
    con otros dígitos), y un txca así llega hasta el SRM."""

    def test_telefono_con_digitos_no_ascii_se_rechaza(self):
        self.armar()
        for tel in ("６１８１２３４５６７",       # ancho completo
                    "٦١٨١٢٣٤٥٦٧",             # arábigo-índico
                    "618123456７"):           # mezcla: "mismo" número que 6181234567
            with self.subTest(telefono=tel):
                r = self.post("/api/registrar", datos_registro(telefono=tel))
                self.assertEqual(r.status_code, 400, r.json)
        self.assertEqual(self.bd.llamadas, [], "Se guardó un teléfono que no es 0-9")

    def test_txca_con_digitos_no_ascii_no_llega_al_srm(self):
        self.armar()
        r = self.post("/api/validar", {"txca": "２０２６-３３７３０８", "fecha_pago": "2026-09-03"})
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.srm.consultas, [])


# ================================================== app.py: formato de fecha
class FallaFechaFueraDelContrato(_Base):
    """El contrato (README y app.py) dice fecha_pago = AAAA-MM-DD, pero
    date.fromisoformat en Python 3.11+ también acepta '20260903' o
    '2026-W36-4' (semana ISO). El comportamiento depende de la versión de
    Python instalada en el servidor."""

    def test_solo_acepta_aaaa_mm_dd(self):
        self.armar()
        for fecha in ("20260903", "2026-W36-4", "2026W364", "2026-246"):
            with self.subTest(fecha=fecha):
                r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": fecha})
                self.assertEqual(r.status_code, 400)
        self.assertEqual(self.srm.consultas, [])


# ================================================== app.py: mensaje de nombre largo
class FallaMensajeDeNombreLargo(_Base):
    """Un nombre de más de 60 letras se rechaza con 'solo puede contener
    letras y espacios', lo cual es falso y confunde al ciudadano. El
    formulario no limita el largo, así que el caso sí llega al servicio."""

    def test_nombre_largo_explica_el_largo(self):
        self.armar()
        r = self.post("/api/registrar", datos_registro(nombre="A" * 61))
        self.assertEqual(r.status_code, 400)
        self.assertNotIn("solo puede contener letras", r.json["mensaje"])


# ================================================== srm.py: respuestas raras
class FallaErroresDelSRMSinControlar(_Base):
    """srm.py solo atrapa ConnectionError, Timeout y ValueError. Otras
    excepciones de requests (ChunkedEncodingError, ContentDecodingError,
    TooManyRedirects...) y un 'error' que no es objeto escapan como
    excepciones genéricas: Flask responde 500 en HTML en lugar de 503 con
    MSG_NO_DISPONIBLE."""

    def _cliente(self, *salidas):
        return ClienteSRM("https://srm", TOKEN_FALSO, SALT_FALSO, sesion=_SesionFalla(*salidas))

    def test_otras_excepciones_de_requests_son_srm_no_disponible(self):
        for exc in (requests.exceptions.ChunkedEncodingError(),
                    requests.exceptions.ContentDecodingError(),
                    requests.exceptions.TooManyRedirects()):
            with self.subTest(excepcion=type(exc).__name__):
                with self.assertRaises(SRMNoDisponible):
                    self._cliente(exc).consultar("2026-337308")

    def test_error_que_no_es_objeto(self):
        for cuerpo in ({"error": "Servicio en mantenimiento"}, {"error": ["ERROR-07"]}):
            with self.subTest(cuerpo=cuerpo):
                with self.assertRaises((TransaccionRechazada, SRMNoDisponible)):
                    self._cliente(_Resp(cuerpo)).consultar("2026-337308")

    def test_la_app_responde_503_en_json(self):
        srm = self._cliente(requests.exceptions.ChunkedEncodingError())
        self.armar(srm=srm)
        r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-09-03"})
        self.assertEqual(r.status_code, 503)
        self.assertTrue(r.is_json)


# ================================================== bd.py: respuesta de Supabase
class FallaRespuestaDeSupabase(unittest.TestCase):
    """bd.py hace bool(datos['success']): el texto "false" es verdadero en
    Python, así que un rechazo se reportaría como registro exitoso. Y
    str(None) le mostraría al ciudadano el mensaje "None"."""

    def _registrar(self, respuesta):
        bd = ClienteSupabase("https://x", "k", sesion=_SesionFalla(_Resp(respuesta)))
        return bd.registrar_boleto(txca="2026-1", nombre="A", apellido_paterno="B",
                                   apellido_materno=None, telefono="6181234567",
                                   clave_catastral="C", propietario="P", direccion="D")

    def test_success_que_no_es_booleano_no_cuenta_como_exito(self):
        for valor in ("false", "0", "no", 0.0001, [False]):
            with self.subTest(success=valor):
                try:
                    r = self._registrar({"success": valor, "message": "x"})
                except BDNoDisponible:
                    continue  # también aceptable: respuesta inesperada
                self.assertIsNot(r["success"], True, "Un rechazo se reportó como éxito")

    def test_mensaje_nulo_no_se_muestra_como_None(self):
        try:
            r = self._registrar({"success": False, "message": None})
        except BDNoDisponible:
            return
        self.assertNotEqual(r["message"], "None")


# ================================================== limites.py
class FallaLimiteDeIntentos(unittest.TestCase):
    def test_ipv6_de_la_misma_red_comparte_limite(self):
        """Cada dirección IPv6 lleva su propia cuenta. Cualquier conexión
        IPv6 doméstica recibe una red /64 (18 trillones de direcciones): el
        límite se esquiva cambiando de dirección en cada intento."""
        lim = LimiteIntentos(2, 600)
        permitidos = sum(lim.permitir(f"2001:db8:1:2::{i:x}") for i in range(10))
        self.assertLessEqual(permitidos, 2)

    def test_las_ips_viejas_se_olvidan(self):
        """Las colas vacías nunca se borran del diccionario: la memoria crece
        con cada IP distinta que haya llegado alguna vez (con IPv6, sin tope)."""
        reloj = [0.0]
        lim = LimiteIntentos(5, 600, reloj=lambda: reloj[0])
        for i in range(5000):
            lim.permitir(f"200.0.{i // 256}.{i % 256}")
        reloj[0] = 10_000  # mucho después de que venció la ventana
        lim.permitir("201.1.1.1")
        self.assertLess(len(lim._intentos), 100,
                        f"Se conservan {len(lim._intentos)} IPs ya vencidas")


# ================================================== supuestos por confirmar
class SupuestoTxcaDelSRM(_Base):
    """El servicio nunca compara predio.txca (lo que contestó el SRM) con el
    txca que pidió. Si el SRM, un proxy o una caché contestara la transacción
    de otra persona, se guardaría un boleto con la clave catastral y el
    propietario de otro predio."""

    def test_no_registra_si_el_srm_contesta_otra_transaccion(self):
        self.armar(srm=SRMFalso({"2026-337308": predio(txca="2026-999999")}), bd=BDFalsa())
        r = self.post("/api/registrar", datos_registro())
        self.assertNotEqual(r.status_code, 200)
        self.assertEqual(self.bd.llamadas, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
