"""Serve demo product photos in local development only."""
from pathlib import Path
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles


def mount_product_media(app: FastAPI) -> None:
    media_directory = Path(__file__).resolve().parent.parent / 'media' / 'products'
    if not media_directory.is_dir():
        raise RuntimeError(f'Missing product images folder: {media_directory}')
    app.mount('/media/products', StaticFiles(directory=str(media_directory)), name='product-media')
