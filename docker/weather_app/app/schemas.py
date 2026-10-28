from pydantic import BaseModel, EmailStr

class UserCreate(BaseModel):
    name: str
    email: EmailStr

class UserOut(BaseModel):
    id: int
    name: str
    email: EmailStr

    class Config:
        from_attributes = True

class PreferenceCreate(BaseModel):
    user_id: int
    city: str
    alert_type: str

class PreferenceOut(BaseModel):
    id: int
    user_id: int
    city: str
    alert_type: str

    class Config:
        from_attributes = True
