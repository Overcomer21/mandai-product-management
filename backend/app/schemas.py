from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict
class ProductInput(BaseModel):
    name:str=Field(min_length=1,max_length=160)
    description:str=Field(default='',max_length=1000)
    category:str=Field(default='Merchandise',max_length=100)
    price:Decimal=Field(ge=0, decimal_places=2)
    stock:int=Field(ge=0)
    is_active:bool=True
    image_url:str=Field(default='',max_length=2048)
    spin_image_urls:str=''
class ProductOut(ProductInput):
    id:int
    model_config=ConfigDict(from_attributes=True)
class Login(BaseModel):
    email:str
    password:str
class PurchaseInput(BaseModel):
    product_id:int=Field(gt=0)
    quantity:int=Field(gt=0,le=1000)
class PurchaseOut(BaseModel):
    order_id:int
    product_id:int
    quantity:int
    total_amount:Decimal
    status:str
    replayed:bool=False

class CheckoutItem(BaseModel):
    product_id:int=Field(gt=0)
    quantity:int=Field(gt=0,le=100)

class CheckoutInput(BaseModel):
    items:list[CheckoutItem]=Field(min_length=1,max_length=30)
    delivery_address:str=Field(min_length=10,max_length=500)
    payment_method:str=Field(pattern='^(card_demo|paynow_demo)$')
    simulate_decline:bool=False
