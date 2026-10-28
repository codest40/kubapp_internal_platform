from sqlalchemy import Column, Integer, String, ForeignKey
from sqlalchemy.orm import relationship
from db import Base

class WeatherUser(Base):
    __tablename__ = "weatherusers"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False)
    preferences = relationship("Preference", back_populates="user")

class Preference(Base):
    __tablename__ = "preferences"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("weatherusers.id"))
    city = Column(String, nullable=False)
    alert_type = Column(String, nullable=False)

    user = relationship("WeatherUser", back_populates="preferences")
