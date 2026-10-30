import os

from sqlalchemy import select
from app.database import SessionLocal
from app.models import User
from app.security import hash_password


def update_passwords():
    accounts = [
        ("admin@demo.local", "DEMO_ADMIN_PASSWORD"),
        ("user@demo.local", "DEMO_USER_PASSWORD"),
    ]

    with SessionLocal() as db:
        try:
            for email, env_name in accounts:
                password = os.environ.get(env_name)

                if not password:
                    raise ValueError(f"{env_name} is not configured")

                user = db.scalar(
                    select(User).where(User.email == email)
                )

                if user is None:
                    raise ValueError(f"Account not found: {email}")

                user.password_hash = hash_password(password)
                print(f"Password updated: {email}")

            db.commit()
            print("All demo passwords updated successfully.")

        except Exception:
            db.rollback()
            raise


if __name__ == "__main__":
    update_passwords()