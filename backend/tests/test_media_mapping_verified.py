from pathlib import Path
from uuid import uuid4
from .conftest import token

# PNG signature + minimal valid 1x1 image.
_PNG = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489'
    '0000000b49444154789c636000020000050001a5f645400000000049454e44ae426082'
)

def test_media_url_roundtrip(test_env):
    client, _ = test_env
    admin = token(client, 'admin@test.local', 'admin-test-secret')
    # Do not depend on a product file already existing on the user's machine.
    media_dir = Path(__file__).resolve().parents[1] / 'media' / 'products'
    media_dir.mkdir(parents=True, exist_ok=True)
    filename = f'pytest_media_{uuid4().hex}.png'
    file_path = media_dir / filename
    file_path.write_bytes(_PNG)
    try:
        url = f'http://127.0.0.1:8000/media/products/{filename}'
        payload = {
            'name': 'Panda Test', 'description': 'demo',
            'category': 'Merchandise', 'price': '29.90',
            'stock': 10, 'is_active': True,
            'image_url': url, 'spin_image_urls': f'{url}\n{url}',
        }
        res = client.post('/api/admin/products', headers=admin, json=payload)
        assert res.status_code == 201, res.text
        assert res.json()['image_url'] == payload['image_url']
        assert res.json()['spin_image_urls'] == payload['spin_image_urls']
        pid = res.json()['id']
        listing = client.get('/api/products')
        assert listing.status_code == 200, listing.text
        product = next(x for x in listing.json() if x['id'] == pid)
        assert product['image_url'] == url
        assert product['spin_image_urls'] == payload['spin_image_urls']
        media_response = client.get(f'/media/products/{filename}')
        assert media_response.status_code == 200
        assert media_response.content == _PNG
        updated_url = f'http://127.0.0.1:8000/media/products/other_{filename}'
        payload['image_url'] = updated_url
        updated = client.put(f'/api/admin/products/{pid}', headers=admin, json=payload)
        assert updated.status_code == 200, updated.text
        assert updated.json()['image_url'] == updated_url
    finally:
        file_path.unlink(missing_ok=True)


def test_product_without_image_has_empty_url(test_env):
    client, _ = test_env
    admin = token(client, 'admin@test.local', 'admin-test-secret')
    payload = {
        'name': 'No Photo Product', 'description': 'demo', 'category': 'Tests',
        'price': '12.50', 'stock': 5, 'is_active': True,
    }
    response = client.post('/api/admin/products', headers=admin, json=payload)
    assert response.status_code == 201, response.text
    assert response.json()['image_url'] == ''
    assert response.json()['spin_image_urls'] == ''
