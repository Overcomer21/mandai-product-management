import os
from sqlalchemy import select
from app.database import SessionLocal
from app.models import User
from app.security import hash_password

def main():
    accounts=[('admin@demo.local','admin','DEMO_ADMIN_PASSWORD'),('user@demo.local','user','DEMO_USER_PASSWORD')]
    with SessionLocal() as db:
        for email,role,env in accounts:
            pw=os.getenv(env)
            if not pw or len(pw)<10:raise RuntimeError(f'Set {env} (at least 10 characters)')
            if not db.scalar(select(User).where(User.email==email)):
                db.add(User(email=email,role=role,password_hash=hash_password(pw)))
        db.commit()
    print('Seed users complete (existing users not modified).')
if __name__=='__main__':main()
