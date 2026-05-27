import os
from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from typing import List

from . import models, schemas, auth
from .database import engine, Base, get_db

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Expert Control API")

# static files
static_dir = os.path.join(os.path.dirname(__file__), "static")
if not os.path.exists(static_dir):
    os.makedirs(static_dir, exist_ok=True)
app.mount("/static", StaticFiles(directory=static_dir), name="static")


def create_default_admin(db: Session):
    admin_username = os.getenv("ADMIN_USER", "admin")
    admin_password = os.getenv("ADMIN_PASSWORD", "admin")
    user = db.query(models.User).filter(models.User.username == admin_username).first()
    if not user:
        hashed = auth.get_password_hash(admin_password)
        user = models.User(username=admin_username, hashed_password=hashed)
        db.add(user)
        db.commit()


@app.on_event("startup")
def startup():
    db = next(get_db())
    create_default_admin(db)


@app.post("/token", response_model=schemas.Token)
def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = auth.authenticate_user(db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    access_token = auth.create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/users", status_code=201)
def create_user(u: schemas.UserCreate, db: Session = Depends(get_db), current=Depends(auth.get_current_user)):
    exists = db.query(models.User).filter(models.User.username == u.username).first()
    if exists:
        raise HTTPException(status_code=400, detail="User exists")
    user = models.User(username=u.username, hashed_password=auth.get_password_hash(u.password))
    db.add(user)
    db.commit()
    return {"msg": "created"}


@app.get("/params", response_model=List[schemas.Param])
def list_params(db: Session = Depends(get_db), current=Depends(auth.get_current_user)):
    items = db.query(models.ExpertParam).all()
    return [schemas.Param(name=i.name, value=i.value) for i in items]


@app.put("/params/{name}")
def set_param(name: str, p: schemas.Param, db: Session = Depends(get_db), current=Depends(auth.get_current_user)):
    item = db.query(models.ExpertParam).filter(models.ExpertParam.name == name).first()
    if not item:
        item = models.ExpertParam(name=name, value=p.value)
        db.add(item)
    else:
        item.value = p.value
    db.commit()
    return {"msg": "ok", "name": name, "value": p.value}


@app.post("/logs", status_code=201)
def post_log(l: schemas.LogIn, db: Session = Depends(get_db), current=Depends(auth.get_current_user)):
    entry = models.LogEntry(level=l.level, message=l.message)
    db.add(entry)
    db.commit()
    return {"msg": "stored"}


@app.get("/logs", response_model=List[schemas.LogOut])
def get_logs(limit: int = 100, db: Session = Depends(get_db), current=Depends(auth.get_current_user)):
    q = db.query(models.LogEntry).order_by(models.LogEntry.id.desc()).limit(limit).all()
    return q


@app.get("/admin", response_class=HTMLResponse)
def admin(request: Request):
    db = next(get_db())
    param_items = db.query(models.ExpertParam).all()
    log_items = db.query(models.LogEntry).order_by(models.LogEntry.id.desc()).limit(200).all()
    
    # Build HTML with params and logs inline
    params_html = ""
    for p in param_items:
        params_html += f'<div class="param-item"><span class="pname">{p.name}</span><input class="pvalue" data-name="{p.name}" value="{p.value}" /><button onclick="updateParam(this)">بروزرسانی</button></div>'
    
    logs_html = ""
    for l in log_items:
        logs_html += f'<div class="log-item">[{l.timestamp}] <strong>{l.level}</strong> - {l.message}</div>'
    
    html_content = f"""<!doctype html>
<html lang="fa">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>Admin - Expert Control</title>
    <link rel="stylesheet" href="/static/admin.css" />
  </head>
  <body>
    <h1>پنل ادمین (Expert Control)</h1>

    <div>
      <label>توکن: </label>
      <input id="token" type="text" placeholder="Paste token here" style="width:60%" />
      <button onclick="saveToken()">ذخیره</button>
    </div>

    <section>
      <h2>پارامترها</h2>
      <div id="params">
        {params_html if params_html else '<div>No params</div>'}
      </div>
    </section>

    <section>
      <h2>لاگ‌ها (آخرین‌ها)</h2>
      <div>
        <button onclick="refreshLogs()">رفرش</button>
      </div>
      <div id="logs">
        {logs_html if logs_html else '<div>No logs</div>'}
      </div>
    </section>

    <script src="/static/admin.js"></script>
  </body>
</html>"""
    return html_content
