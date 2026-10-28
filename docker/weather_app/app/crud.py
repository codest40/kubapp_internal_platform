from sqlalchemy.orm import Session
from models import WeatherUser, Preference
from schemas import UserCreate, PreferenceCreate

def create_user(db: Session, user: UserCreate):
    db_user = WeatherUser(name=user.name, email=user.email)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

def get_user(db: Session, user_id: int):
    return db.query(WeatherUser).filter(WeatherUser.id == user_id).first()

def create_preference(db: Session, pref: PreferenceCreate):
    db_pref = Preference(user_id=pref.user_id, city=pref.city, alert_type=pref.alert_type)
    db.add(db_pref)
    db.commit()
    db.refresh(db_pref)
    return db_pref

def get_preferences_by_user(db: Session, user_id: int):
    return db.query(Preference).filter(Preference.user_id == user_id).all()
