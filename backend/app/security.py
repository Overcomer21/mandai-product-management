import os
from datetime import datetime, timedelta, timezone
import jwt
from jwt import InvalidTokenError
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from .database import get_db
from .models import User

ph=PasswordHasher()
bearer=HTTPBearer(auto_error=False)
def hash_password(password): return ph.hash(password)
def verify_password(password, encoded):
    try: return ph.verify(encoded,password)
    except (VerifyMismatchError, VerificationError): return False

def issue_token(user):
    secret=os.getenv('JWT_SECRET','')
    if len(secret)<32: raise RuntimeError('JWT_SECRET must be configured (at least 32 characters)')
    data={'sub':str(user.id),'exp':datetime.now(timezone.utc)+timedelta(hours=4)}
    return jwt.encode(data,secret,algorithm='HS256')

def current_user(credentials:HTTPAuthorizationCredentials|None=Depends(bearer),db:Session=Depends(get_db)):
    if not credentials:raise HTTPException(401,'Authentication required',headers={'WWW-Authenticate':'Bearer'})
    try:
        data=jwt.decode(credentials.credentials,os.environ['JWT_SECRET'],algorithms=['HS256'])
        user=db.get(User,int(data['sub']))
    except (InvalidTokenError,ValueError,KeyError,TypeError):
        user=None
    if user is None:raise HTTPException(401,'Invalid or expired token',headers={'WWW-Authenticate':'Bearer'})
    return user

def admin_only(user:User=Depends(current_user)):
    if user.role!='admin':raise HTTPException(403,'Admin role required')
    return user
