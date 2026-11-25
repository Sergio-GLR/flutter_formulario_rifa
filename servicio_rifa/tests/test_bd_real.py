"""
Pruebas contra un PostgreSQL de verdad con base_datos/esquema.sql cargado.

Se saltan si no están las variables (ver base_datos/compose.pruebas.yaml):
    PRUEBAS_BD_ADMIN  dueño de la base: limpia las tablas entre pruebas
    PRUEBAS_BD_URL    rol rifa_servicio: el mismo con que se conecta el servicio

NUNCA apuntar estas variables a la base del servidor: cada prueba BORRA las tablas.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import psycopg  # noqa: E402

from app import RECHAZOS_DE_LA_BD  # noqa: E402
from bd import ClientePostgres  # noqa: E402

ADMIN = os.environ.get("PRUEBAS_BD_ADMIN", "")
APP = os.environ.get("PRUEBAS_BD_URL", "")

YA_REGISTRADO = "Este número de transacción ya fue registrado anteriormente."
LIMITE_TELEFONO = "Este número de teléfono ya ha alcanzado el límite de 5 boletos registrados en total."


def boleto(txca="2026-337308", telefono="6181234567", **cambios):
    datos = dict(txca=txca, nombre="ANA", apellido_paterno="GARCÍA", apellido_materno="LÓPEZ",
                 telefono=telefono, clave_catastral="10-001-005", propietario="ANA GARCÍA LÓPEZ",
                 direccion="CALLE 5 DE FEBRERO 100, ZONA CENTRO")
    datos.update(cambios)
    return datos


@unittest.skipUnless(ADMIN and APP, "Sin PRUEBAS_BD_ADMIN / PRUEBAS_BD_URL (ver base_datos/compose.pruebas.yaml)")
class BDReal(unittest.TestCase):
    def setUp(self):
        with psycopg.connect(ADMIN, autocommit=True) as c:
            c.execute('TRUNCATE public."Boletos_Rifa", public."Pagadores", public."Predios"')
        self.bd = ClientePostgres(APP)

    def contar(self, tabla):
        with psycopg.connect(ADMIN) as c:
            return c.execute(f'SELECT count(*) FROM public."{tabla}"').fetchone()[0]

    def test_registra_un_boleto(self):
        r = self.bd.registrar_boleto(**boleto())
        self.assertEqual(r, {"success": True, "message": "Registro completado exitosamente."})
        self.assertEqual(self.contar("Boletos_Rifa"), 1)

    def test_el_mismo_folio_no_da_otro_boleto(self):
        self.bd.registrar_boleto(**boleto())
        r = self.bd.registrar_boleto(**boleto(telefono="6189999999"))
        self.assertEqual(r, {"success": False, "message": YA_REGISTRADO})
        self.assertEqual(self.contar("Boletos_Rifa"), 1)

    def test_maximo_5_boletos_por_telefono_aunque_se_escriba_distinto(self):
        for i in range(5):
            self.assertTrue(self.bd.registrar_boleto(**boleto(txca=f"2026-10000{i}"))["success"])
        r = self.bd.registrar_boleto(**boleto(txca="2026-200000", telefono="+52 618 123 4567"))
        self.assertEqual(r, {"success": False, "message": LIMITE_TELEFONO})

    def test_sin_apellido_materno_no_duplica_al_pagador(self):
        self.bd.registrar_boleto(**boleto(txca="2026-1", apellido_materno=None))
        self.bd.registrar_boleto(**boleto(txca="2026-2", apellido_materno=None))
        self.assertEqual(self.contar("Pagadores"), 1)

    def test_los_rechazos_de_la_bd_son_los_que_app_py_deja_pasar(self):
        """app.py solo muestra los rechazos de RECHAZOS_DE_LA_BD: si la función
        cambia su texto, el ciudadano vería el mensaje genérico."""
        self.bd.registrar_boleto(**boleto())
        self.assertIn(self.bd.registrar_boleto(**boleto())["message"], RECHAZOS_DE_LA_BD)
        for i in range(4):
            self.bd.registrar_boleto(**boleto(txca=f"2026-30000{i}"))
        self.assertIn(self.bd.registrar_boleto(**boleto(txca="2026-400000"))["message"],
                      RECHAZOS_DE_LA_BD)

    def test_el_rol_del_servicio_solo_puede_registrar(self):
        """rifa_servicio no lee ni escribe tablas ni llama a otras funciones:
        si alguien roba su contraseña, no puede descargar el padrón."""
        with psycopg.connect(APP, autocommit=True) as c:
            for sql in ('SELECT * FROM public."Pagadores"',
                        'DELETE FROM public."Boletos_Rifa"',
                        "SELECT * FROM public.obtener_boletos_impresion()"):
                with self.subTest(sql=sql), self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    c.execute(sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
