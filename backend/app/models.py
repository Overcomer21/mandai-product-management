from datetime import datetime, timezone
from decimal import Decimal
from sqlalchemy import String, Integer, Numeric, DateTime, ForeignKey, UniqueConstraint, CheckConstraint, Boolean, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .database import Base

class User(Base):
    __tablename__='Users'
    id:Mapped[int]=mapped_column('Id',Integer,primary_key=True,autoincrement=True)
    email:Mapped[str]=mapped_column('Email',String(255),unique=True,nullable=False)
    password_hash:Mapped[str]=mapped_column('PasswordHash',String(255),nullable=False)
    role:Mapped[str]=mapped_column('Role',String(20),nullable=False)
    delivery_address:Mapped[str|None]=mapped_column('DeliveryAddress',String(255),nullable=True)
    phone_number:Mapped[str|None]=mapped_column('PhoneNumber',String(50),nullable=True)
    payment_method:Mapped[str|None]=mapped_column('PaymentMethod',String(150),nullable=True)
    __table_args__=(CheckConstraint("Role IN ('admin', 'user')",name='CK_Users_Role'),)

class Product(Base):
    __tablename__='Products'
    id:Mapped[int]=mapped_column('Id',Integer,primary_key=True,autoincrement=True)
    name:Mapped[str]=mapped_column('Name',String(160),nullable=False)
    description:Mapped[str]=mapped_column('Description',String(1000),nullable=False,default='')
    category:Mapped[str]=mapped_column('Category',String(100),nullable=False,default='Merchandise')
    price:Mapped[Decimal]=mapped_column('Price',Numeric(18,2),nullable=False)
    stock:Mapped[int]=mapped_column('Stock',Integer,nullable=False)
    is_active:Mapped[bool]=mapped_column('IsActive',Boolean,nullable=False,default=True)
    image_url:Mapped[str]=mapped_column('ImageUrl',String(2048),nullable=False,default='')
    spin_image_urls:Mapped[str]=mapped_column('SpinImageUrls',String,nullable=False,default='')
    __table_args__=(CheckConstraint('Price >= 0',name='CK_Products_Price'),CheckConstraint('Stock >= 0',name='CK_Products_Stock'))

class Order(Base):
    __tablename__='Orders'
    id:Mapped[int]=mapped_column('Id',Integer,primary_key=True,autoincrement=True)
    user_id:Mapped[int]=mapped_column('UserId',ForeignKey('Users.Id'),nullable=False)
    idempotency_key:Mapped[str]=mapped_column('IdempotencyKey',String(128),nullable=False)
    request_fingerprint:Mapped[str]=mapped_column('RequestFingerprint',String(64),nullable=False)
    total_amount:Mapped[Decimal]=mapped_column('TotalAmount',Numeric(18,2),nullable=False)
    status:Mapped[str]=mapped_column('Status',String(20),nullable=False,default='completed')
    delivery_address:Mapped[str|None]=mapped_column('DeliveryAddress',String(500),nullable=True)
    created_at:Mapped[datetime]=mapped_column('CreatedAt',DateTime(timezone=True),server_default=func.current_timestamp())
    items:Mapped[list['OrderItem']]=relationship(back_populates='order')
    __table_args__=(UniqueConstraint('UserId','IdempotencyKey',name='UQ_Orders_User_Key'),)

class OrderItem(Base):
    __tablename__='OrderItems'
    id:Mapped[int]=mapped_column('Id',Integer,primary_key=True,autoincrement=True)
    order_id:Mapped[int]=mapped_column('OrderId',ForeignKey('Orders.Id'),nullable=False)
    product_id:Mapped[int]=mapped_column('ProductId',ForeignKey('Products.Id'),nullable=False)
    quantity:Mapped[int]=mapped_column('Quantity',Integer,nullable=False)
    unit_price:Mapped[Decimal]=mapped_column('UnitPrice',Numeric(18,2),nullable=False)
    order:Mapped[Order]=relationship(back_populates='items')
    __table_args__=(CheckConstraint('Quantity > 0',name='CK_OrderItems_Quantity'),)


class Payment(Base):
    __tablename__ = 'Payments'
    id:Mapped[int] = mapped_column('Id',Integer,primary_key=True,autoincrement=True)
    order_id:Mapped[int] = mapped_column('OrderId',ForeignKey('Orders.Id'),nullable=False,unique=True)
    method:Mapped[str] = mapped_column('Method',String(30),nullable=False)
    provider_reference:Mapped[str] = mapped_column('ProviderReference',String(100),nullable=False,unique=True)
    card_last4:Mapped[str] = mapped_column('CardLast4',String(4),nullable=True)
    amount:Mapped[Decimal] = mapped_column('Amount',Numeric(18,2),nullable=False)
    status:Mapped[str] = mapped_column('Status',String(20),nullable=False)
    created_at:Mapped[datetime] = mapped_column('CreatedAt',DateTime(timezone=True),server_default=func.current_timestamp())
