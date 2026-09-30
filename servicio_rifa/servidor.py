"""
Arranque para el servidor municipal (producción), con waitress:

    python servidor.py

Lee la configuración de .env (junto a este archivo) o de las variables de
entorno del sistema. Escucha solo en 127.0.0.1: el proxy del servidor
(IIS, Nginx o Apache) es quien lo publica bajo /api.
"""

import logging
import os

from dotenv import load_dotenv
from waitress import serve

from app import MAX_CUERPO_BYTES, crear_app

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")

if __name__ == "__main__":
    # max_request_body_size: waitress guarda el cuerpo completo (en disco si
    # pasa de 512 KB) ANTES de entregarlo a Flask; su tope por defecto es 1 GB.
    serve(crear_app(), host="127.0.0.1", port=int(os.environ.get("PUERTO", "8080")),
          threads=8, max_request_body_size=MAX_CUERPO_BYTES)
