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

from app import crear_app

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")

if __name__ == "__main__":
    serve(crear_app(), host="127.0.0.1", port=int(os.environ.get("PUERTO", "8080")),
          threads=8)
