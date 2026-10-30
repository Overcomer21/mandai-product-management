"""Generate local Mandai FastAPI secrets, preserving existing .env settings.

Run from anywhere: python generate_mandai_env.py
By default writes to backend/.env alongside this script, or pass --env PATH.
"""
import argparse
import secrets
from pathlib import Path


def update_env(path: Path, rotate: bool = False) -> dict[str, str]:
    existing = path.read_text(encoding='utf-8').splitlines() if path.exists() else []
    updates = {
        'DB_TRUST_CERT': 'yes',
        'CORS_ORIGINS': 'http://localhost:3000,http://localhost:8080',
    }
    values = {}
    for line in existing:
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    for key in ('JWT_SECRET', 'DEMO_ADMIN_PASSWORD', 'DEMO_USER_PASSWORD'):
        current = values.get(key, '')
        placeholder = not current or current.startswith('REPLACE_') or current.startswith('CHANGE_')
        if rotate or placeholder:
            updates[key] = (secrets.token_urlsafe(48) if key == 'JWT_SECRET'
                            else secrets.token_urlsafe(20))
    out = []
    seen = set()
    for line in existing:
        if '=' in line and not line.lstrip().startswith('#'):
            key = line.split('=', 1)[0].strip()
            if key in updates:
                out.append(f'{key}={updates[key]}')
                seen.add(key)
                continue
        out.append(line)
    for key, value in updates.items():
        if key not in seen:
            out.append(f'{key}={value}')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return {**values, **updates}


def main():
    parser = argparse.ArgumentParser(description='Generate Mandai development .env secrets')
    parser.add_argument('--env', type=Path, default=Path(__file__).resolve().parent / 'backend' / '.env')
    parser.add_argument('--rotate', action='store_true', help='Replace existing secrets (may invalidate JWTs and demo login credentials)')
    args = parser.parse_args()
    values = update_env(args.env, args.rotate)
    print(f'Environment file updated: {args.env.resolve()}')
    print('Keep this file out of Git. Secrets are not printed.')
    print('New demo passwords take effect in the database only after you update/seed user hashes.')
    for key in ('DB_TRUST_CERT', 'CORS_ORIGINS'):
        print(f'{key}={values[key]}')


if __name__ == '__main__':
    main()
