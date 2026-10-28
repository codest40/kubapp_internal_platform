# localtz.py
from datetime import datetime
try:
    import pytz
except ImportError:
    pytz = None

if pytz:
  LOCAL_TZ = pytz.timezone("Africa/Lagos")
  def timer() -> str:
      return datetime.now(LOCAL_TZ).strftime("%Y:%m:%d_%H:%M:%S")
else:
  def timer() -> str:
      return datetime.now().strftime("%Y:%m:%d_%H:%M:%S")

