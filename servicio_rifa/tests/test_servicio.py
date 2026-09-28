"""
Tests del servicio interno. No tocan el SRM ni Supabase reales: ambos se
simulan. Correr desde la carpeta servicio_rifa:

    python -m unittest -v tests.test_servicio
"""

import os
import sys
import unittest
from datetime import date

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import MSG_LIMITE, MSG_NO_ENCONTRADO, MSG_PERSONA_MORAL, crear_app  # noqa: E402
from bd import BDNoDisponible, ClienteSupabase  # noqa: E402
from limites import LimiteIntentos  # noqa: E402
from srm import (ClienteSRM, Predio, SRMNoDisponible, TransaccionRechazada,  # noqa: E402
                 firmar)

TOKEN_FALSO = "t" * 64
SALT_FALSO = "s" * 64


def predio(txca="2026-337308", persona="FISICA", fecha=date(2026, 9, 3)):
    return Predio(txca=txca, clave_catastral="10-001-005-03-0001", propietario="PROPIETARIO OFICIAL",
                  domicilio="CALLE OFICIAL 120", tipo_persona=persona, fecha_pago=fecha)


class SRMFalso:
    def __init__(self, respuestas=None):
        self.respuestas = respuestas or {}
        self.consultas = []

    def consultar(self, txca):
        self.consultas.append(txca)
        r = self.respuestas.get(txca, TransaccionRechazada("ERROR-99", "No existe"))
        if isinstance(r, Exception):
            raise r
        return r


class BDFalsa:
    def __init__(self, resultado=None, error=None):
        self.resultado = resultado or {"success": True, "message": "Registro completado exitosamente."}
        self.error = error
        self.llamadas = []

    def registrar_boleto(self, **kw):
        self.llamadas.append(kw)
        if self.error:
            raise self.error
        return self.resultado


def datos_registro(**cambios):
    d = {"txca": "2026-337308", "fecha_pago": "2026-09-03", "nombre": "Ana",
         "apellido_paterno": "López", "apellido_materno": "Soto", "telefono": "6181234567"}
    d.update(cambios)
    return d


class _Base(unittest.TestCase):
    def armar(self, srm=None, bd=None, limite=None, config=None):
        self.srm = srm or SRMFalso({"2026-337308": predio()})
        self.bd = bd or BDFalsa()
        self.limite = limite or LimiteIntentos(1000, 600, ["10.0.0.0/8"])
        app = crear_app(srm=self.srm, bd=self.bd, limite=self.limite, config=config or {})
        self.cliente = app.test_client()

    def post(self, ruta, datos, ip="200.1.1.1", **kw):
        return self.cliente.post(ruta, json=datos, environ_base={"REMOTE_ADDR": ip}, **kw)


# ================================================== hallazgo 2: verificación
class VerificacionAntesDeRegistrar(_Base):
    def test_transaccion_inventada_no_se_registra(self):
        self.armar()
        r = self.post("/api/registrar", datos_registro(txca="2026-999999"))
        self.assertEqual(r.status_code, 422)
        self.assertEqual(r.json["mensaje"], MSG_NO_ENCONTRADO)
        self.assertEqual(self.bd.llamadas, [], "Se llamó a Supabase con una transacción no válida")

    def test_persona_moral_no_se_registra(self):
        self.armar(srm=SRMFalso({"2026-337308": predio(persona="MORAL")}))
        r = self.post("/api/registrar", datos_registro())
        self.assertEqual((r.status_code, r.json["mensaje"]), (422, MSG_PERSONA_MORAL))
        self.assertEqual(self.bd.llamadas, [])

    def test_datos_del_predio_salen_del_srm_no_de_la_peticion(self):
        self.armar()
        falsos = datos_registro(clave_catastral="FALSA", propietario="IMPOSTOR",
                                direccion="Dirección falsa", p_clave_catastral="FALSA")
        r = self.post("/api/registrar", falsos)
        self.assertEqual(r.status_code, 200, r.json)
        guardado = self.bd.llamadas[0]
        self.assertEqual(guardado["clave_catastral"], "10-001-005-03-0001")
        self.assertEqual(guardado["propietario"], "PROPIETARIO OFICIAL")
        self.assertEqual(guardado["direccion"], "CALLE OFICIAL 120")

    def test_registrar_vuelve_a_consultar_el_srm(self):
        """Aunque el navegador diga que ya validó, registrar consulta de nuevo."""
        self.armar()
        self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-09-03"})
        self.post("/api/registrar", datos_registro())
        self.assertEqual(self.srm.consultas, ["2026-337308", "2026-337308"])


# ============================================ hallazgo 3: fecha de pago
class FechaDePago(_Base):
    def test_fecha_correcta_permite_registrar(self):
        self.armar()
        r = self.post("/api/registrar", datos_registro())
        self.assertEqual(r.status_code, 200, r.json)
        self.assertEqual(r.json["boleto"], {"txca": "2026-337308", "nombre": "ANA LÓPEZ SOTO"})

    def test_folio_ajeno_sin_la_fecha_no_se_registra(self):
        self.armar()
        r = self.post("/api/registrar", datos_registro(fecha_pago="2026-09-04"))
        self.assertEqual((r.status_code, r.json["mensaje"]), (422, MSG_NO_ENCONTRADO))
        self.assertEqual(self.bd.llamadas, [])

    def test_fecha_incorrecta_no_revela_la_direccion(self):
        self.armar()
        r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-01-01"})
        self.assertEqual(r.status_code, 422)
        self.assertNotIn("direccion", r.json)

    def test_folio_inexistente_y_fecha_incorrecta_dan_el_mismo_mensaje(self):
        """Así nadie puede averiguar qué folios existen probando."""
        self.armar()
        inexistente = self.post("/api/validar", {"txca": "2026-000001", "fecha_pago": "2026-09-03"})
        fecha_mala = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-01-01"})
        self.assertEqual(inexistente.json, fecha_mala.json)
        self.assertEqual(inexistente.status_code, fecha_mala.status_code)


# ============================================ privacidad de la respuesta
class Privacidad(_Base):
    def test_validar_solo_devuelve_la_direccion(self):
        self.armar()
        r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-09-03"})
        self.assertEqual(r.json, {"ok": True, "direccion": "CALLE OFICIAL 120"})

    def test_ninguna_respuesta_contiene_secretos(self):
        srm_real = ClienteSRM("https://srm.invalido", TOKEN_FALSO, SALT_FALSO,
                              sesion=_SesionFalla(requests.ConnectionError()))
        self.armar(srm=srm_real)
        for ruta, datos in (("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"}),
                            ("/api/registrar", datos_registro())):
            cuerpo = self.post(ruta, datos).get_data(as_text=True)
            self.assertNotIn(TOKEN_FALSO, cuerpo)
            self.assertNotIn(SALT_FALSO, cuerpo)
        self.assertNotIn(TOKEN_FALSO, repr(srm_real))

    def test_error_de_bd_no_expone_detalles(self):
        self.armar(bd=BDFalsa(error=BDNoDisponible('relation "Predios" violates not-null')))
        r = self.post("/api/registrar", datos_registro())
        self.assertEqual(r.status_code, 503)
        self.assertNotIn("Predios", r.get_data(as_text=True))


# ============================================ validación de entradas
class Entradas(_Base):
    def test_formatos_invalidos_no_llegan_al_srm(self):
        self.armar()
        casos = [
            {"txca": "337308", "fecha_pago": "2026-09-03"},
            {"txca": "2026-33a308", "fecha_pago": "2026-09-03"},
            {"txca": "2026-337308", "fecha_pago": "03/09/2026"},
            {"txca": "2026-337308"},
            {},
        ]
        for datos in casos:
            with self.subTest(datos=datos):
                self.assertEqual(self.post("/api/validar", datos).status_code, 400)
        self.assertEqual(self.srm.consultas, [])

    def test_telefono_y_nombres(self):
        self.armar()
        malos = [datos_registro(telefono="618123456"), datos_registro(telefono="61812345678"),
                 datos_registro(nombre=""), datos_registro(nombre="Ana<script>"),
                 datos_registro(apellido_paterno="Lopez2"), datos_registro(nombre="A" * 61)]
        for datos in malos:
            with self.subTest(datos=datos):
                self.assertEqual(self.post("/api/registrar", datos).status_code, 400)
        self.assertEqual(self.bd.llamadas, [])

    def test_casos_validos_del_formulario(self):
        self.armar()
        for cambios in ({"apellido_paterno": "Güereca"}, {"apellido_materno": ""},
                        {"apellido_materno": None}, {"nombre": "  José   María "}):
            with self.subTest(cambios=cambios):
                r = self.post("/api/registrar", datos_registro(**cambios))
                self.assertEqual(r.status_code, 200, r.json)
        sin_materno = self.bd.llamadas[1]
        self.assertIsNone(sin_materno["apellido_materno"])
        self.assertEqual(self.bd.llamadas[3]["nombre"], "JOSÉ MARÍA")

    def test_rechazo_de_negocio_de_la_bd_se_muestra(self):
        msg = "Este número de teléfono ya ha alcanzado el límite de 5 boletos registrados en total."
        self.armar(bd=BDFalsa(resultado={"success": False, "message": msg}))
        r = self.post("/api/registrar", datos_registro())
        self.assertEqual((r.status_code, r.json["mensaje"]), (422, msg))


# ============================================ límite de intentos
class LimiteDeIntentos(_Base):
    def test_ip_de_internet_se_limita(self):
        self.armar(limite=LimiteIntentos(3, 600, ["10.0.0.0/8"]))
        codigos = [self.post("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"}).status_code
                   for _ in range(4)]
        self.assertEqual(codigos, [422, 422, 422, 429])
        r = self.post("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"})
        self.assertEqual(r.json["mensaje"], MSG_LIMITE)

    def test_modulos_de_la_red_interna_no_se_limitan(self):
        self.armar(limite=LimiteIntentos(3, 600, ["10.0.0.0/8"]))
        codigos = {self.post("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"},
                             ip="10.20.30.40").status_code for _ in range(20)}
        self.assertNotIn(429, codigos)

    def test_cada_ip_lleva_su_cuenta(self):
        self.armar(limite=LimiteIntentos(2, 600))
        for _ in range(2):
            self.post("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"}, ip="200.0.0.1")
        r = self.post("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"}, ip="200.0.0.2")
        self.assertNotEqual(r.status_code, 429)

    def test_la_ventana_se_libera_con_el_tiempo(self):
        reloj = [0.0]
        lim = LimiteIntentos(2, 600, reloj=lambda: reloj[0])
        self.assertTrue(lim.permitir("1.1.1.1") and lim.permitir("1.1.1.1"))
        self.assertFalse(lim.permitir("1.1.1.1"))
        reloj[0] = 601
        self.assertTrue(lim.permitir("1.1.1.1"))

    def test_detras_del_proxy_se_usa_la_ip_real(self):
        """Sin NUMERO_PROXIES todas las peticiones parecerían venir del proxy
        (red interna) y el límite no serviría."""
        self.armar(limite=LimiteIntentos(2, 600, ["10.0.0.0/8"]), config={"NUMERO_PROXIES": "1"})
        cab = {"X-Forwarded-For": "200.5.5.5"}
        codigos = [self.post("/api/validar", {"txca": "2026-1", "fecha_pago": "2026-09-03"},
                             ip="10.0.0.1", headers=cab).status_code for _ in range(3)]
        self.assertEqual(codigos[-1], 429)

    def test_origen_no_permitido(self):
        self.armar(config={"ORIGENES_PERMITIDOS": "https://rifa.municipiodurango.gob.mx"})
        r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-09-03"},
                      headers={"Origin": "https://sitio-ajeno.com"})
        self.assertEqual(r.status_code, 403)
        r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-09-03"},
                      headers={"Origin": "https://rifa.municipiodurango.gob.mx"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.headers["Access-Control-Allow-Origin"],
                         "https://rifa.municipiodurango.gob.mx")


# ============================================ cliente del SRM
class _Resp:
    def __init__(self, datos, status=200):
        self._datos, self.status_code = datos, status

    def json(self):
        if isinstance(self._datos, Exception):
            raise self._datos
        return self._datos


class _SesionFalla:
    """Sesión HTTP falsa: devuelve (o lanza) lo que se le indique, en orden."""

    def __init__(self, *salidas):
        self.salidas = list(salidas)
        self.enviados = []   # cuerpo ya interpretado como dict
        self.crudos = []     # bytes exactos enviados (cuando se usa data=)
        self.cabeceras = []

    def post(self, url, json=None, data=None, headers=None, **kw):
        import json as _json
        self.crudos.append(data)
        self.cabeceras.append(headers or {})
        self.enviados.append(json if json is not None else _json.loads(data))
        s = self.salidas.pop(0) if len(self.salidas) > 1 else self.salidas[0]
        if isinstance(s, Exception):
            raise s
        return s


OK_SRM = {"response": {"cc": "10-001", "propietario": "X", "domicilio": "CALLE 1",
                       "t_persona": "FISICA", "txca": "2026-337308",
                       "fecha_pago": "03-09-2026 13:24:31"}}


class ClienteDelSRM(unittest.TestCase):
    def cliente(self, *salidas):
        self.sesion = _SesionFalla(*salidas)
        return ClienteSRM("https://srm", TOKEN_FALSO, SALT_FALSO, sesion=self.sesion)

    def test_envia_la_firma_hmac(self):
        c = self.cliente(_Resp(OK_SRM))
        p = c.consultar("2026-337308")
        enviado = self.sesion.enviados[0]
        # Valor de referencia FIJO (HMAC-SHA256, salt como texto) calculado aparte.
        # Compararlo contra firmar() mismo no probaría nada. Con los valores reales
        # la firma se verificó contra el ejemplo de la sección 6 de la documentación.
        esperado = "df9558f5f46725022e75a926837a8776cdabc134f4a18b73b17a61819ad6f166"
        self.assertEqual(firmar("2026-337308", TOKEN_FALSO, SALT_FALSO), esperado)
        self.assertEqual(enviado["signature"], esperado)
        self.assertEqual(enviado["token"], TOKEN_FALSO)
        self.assertEqual(p.fecha_pago, date(2026, 9, 3))

    def test_envia_json_compacto_como_flutter(self):
        """Con espacios (lo que hace requests con json=) el SRM responde 500 vacío.
        El formulario de Flutter mandaba JSON compacto y sí funcionaba."""
        c = self.cliente(_Resp(OK_SRM))
        c.consultar("2026-337308")
        crudo = self.sesion.crudos[0]
        self.assertIsInstance(crudo, bytes, "El cuerpo debe mandarse como texto ya armado")
        firma = firmar("2026-337308", TOKEN_FALSO, SALT_FALSO)
        esperado = ('{"txca":"2026-337308","signature":"%s","token":"%s"}'
                    % (firma, TOKEN_FALSO)).encode()
        self.assertEqual(crudo, esperado)
        self.assertNotIn(b" ", crudo)
        self.assertEqual(self.sesion.cabeceras[0]["Content-Type"],
                         "application/json; charset=utf-8")

    def test_reintenta_una_vez_ante_error_de_red(self):
        c = self.cliente(requests.ConnectionError(), _Resp(OK_SRM))
        self.assertEqual(c.consultar("2026-337308").domicilio, "CALLE 1")
        self.assertEqual(len(self.sesion.enviados), 2)

    def test_no_reintenta_mas_de_una_vez(self):
        c = self.cliente(requests.Timeout())
        with self.assertRaises(SRMNoDisponible):
            c.consultar("2026-337308")
        self.assertEqual(len(self.sesion.enviados), 2)

    def test_no_reintenta_un_rechazo_de_negocio(self):
        c = self.cliente(_Resp({"error": {"codigo": "ERROR-07", "mensaje": "Signature"}}))
        with self.assertRaises(TransaccionRechazada):
            c.consultar("2026-337308")
        self.assertEqual(len(self.sesion.enviados), 1)

    def test_respuestas_raras(self):
        for resp in (_Resp(ValueError("no json"), 502), _Resp({}), _Resp({"response": {"cc": "1"}}),
                     _Resp({"response": dict(OK_SRM["response"], fecha_pago="2026/09/03")})):
            with self.subTest(resp=resp._datos):
                with self.assertRaises(SRMNoDisponible):
                    self.cliente(resp).consultar("2026-337308")

    def test_respuesta_no_json_se_describe_en_el_log_sin_secretos(self):
        firma = firmar("2026-337308", TOKEN_FALSO, SALT_FALSO)
        resp = _Resp(ValueError("no json"), 500)
        resp.text = (f"<html><h1>Internal Server Error</h1> token={TOKEN_FALSO} "
                     f"salt={SALT_FALSO} sig={firma}</html>")
        with self.assertRaises(SRMNoDisponible) as ctx:
            self.cliente(resp).consultar("2026-337308")
        detalle = str(ctx.exception)
        self.assertIn("HTTP 500", detalle)
        self.assertIn("Internal Server Error", detalle)
        for secreto in (TOKEN_FALSO, SALT_FALSO, firma):
            self.assertNotIn(secreto, detalle)

    def test_configuracion_incompleta(self):
        with self.assertRaises(ValueError):
            ClienteSRM("https://srm", "", SALT_FALSO)


class ClienteDeSupabase(unittest.TestCase):
    def test_envia_los_parametros_de_la_funcion(self):
        sesion = _SesionFalla(_Resp({"success": True, "message": "ok"}))
        bd = ClienteSupabase("https://x.supabase.co/", "sb_secret_falsa", sesion=sesion)
        r = bd.registrar_boleto(txca="2026-1", nombre="ANA", apellido_paterno="LÓPEZ",
                                apellido_materno=None, telefono="6181234567",
                                clave_catastral="CC", propietario="P", direccion="D")
        self.assertEqual(r, {"success": True, "message": "ok"})
        self.assertEqual(sorted(sesion.enviados[0]), sorted([
            "p_numero_transaccion", "p_nombre_pagador", "p_apellido_paterno", "p_apellido_materno",
            "p_telefono_pagador", "p_clave_catastral", "p_propietario_registrado",
            "p_direccion_predio"]))
        self.assertNotIn("sb_secret_falsa", repr(bd))

    def test_errores(self):
        for salida in (requests.ConnectionError(), _Resp({"message": "x"}, status=401),
                       _Resp({"raro": 1})):
            with self.subTest(salida=salida):
                bd = ClienteSupabase("https://x", "k", sesion=_SesionFalla(salida))
                with self.assertRaises(BDNoDisponible):
                    bd.registrar_boleto(txca="1", nombre="A", apellido_paterno="B",
                                        apellido_materno=None, telefono="1", clave_catastral="C",
                                        propietario="P", direccion="D")


if __name__ == "__main__":
    unittest.main(verbosity=2)
