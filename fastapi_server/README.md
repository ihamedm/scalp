FastAPI Expert Control

این سرویس یک API ساده برای ارتباط Expert Advisor متاتریدر با سرور است. اکسپرت می‌تواند لاگ ارسال کند و بعضی پارامترها را روی سرور ثبت یا دریافت کند. داشبورد ادمین فعلی هم یک صفحه ساده برای دیدن لاگ‌ها و تغییر پارامترهاست.

## راه‌اندازی سریع

1. ساخت virtualenv و نصب وابستگی‌ها:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. اجرای سرور:

```bash
uvicorn fastapi_server.main:app --host 0.0.0.0 --port 8000 --reload
```

3. کاربر پیش‌فرض ادمین:

```text
username: admin
password: admin
```

می‌توانی مقدارها را با env varهای زیر تغییر بدهی:

```bash
export ADMIN_USER=your_user
export ADMIN_PASSWORD=your_password
export SECRET_KEY=change-this-secret
```

نکته: در پیاده‌سازی فعلی، فایل `.env` به‌صورت خودکار خوانده نمی‌شود. یعنی اگر فقط فایل `.env` بسازی، FastAPI لزوماً آن را نمی‌خواند مگر اینکه قبل از اجرای `uvicorn` متغیرها را وارد محیط کنی، یا بعداً `python-dotenv` و `load_dotenv()` به پروژه اضافه شود.

## مکانیزم احراز هویت فعلی

احراز هویت فعلی با JWT Bearer Token انجام می‌شود، نه session/cookie و نه صفحه login کلاسیک.

جریان فعلی این است:

1. کاربر با username/password به endpoint `/token` درخواست می‌زند.
2. سرور اگر username/password درست باشد، یک JWT برمی‌گرداند.
3. برای درخواست‌های محافظت‌شده مثل `/logs` و `/params` باید این توکن در header ارسال شود:

```text
Authorization: Bearer <TOKEN>
```

endpointهای محافظت‌شده:

```text
GET  /params
PUT  /params/{name}
POST /logs
GET  /logs
```

endpointهای بدون توکن:

```text
POST /token
GET  /admin
```

## چرا توکن در داشبورد بعد از refresh پاک می‌شود؟

داشبورد فعلی صفحه login واقعی ندارد. در `static/admin.js` توکن فقط داخل یک متغیر JavaScript به نام `savedToken` ذخیره می‌شود:

```js
let savedToken = ''
```

وقتی در داشبورد توکن را وارد می‌کنی و دکمه ذخیره را می‌زنی، توکن فقط در حافظه همان صفحه نگه داشته می‌شود. با refresh شدن صفحه، JavaScript از اول اجرا می‌شود و مقدار `savedToken` دوباره خالی می‌شود. به همین دلیل بعد از refresh، وقتی دکمه رفرش لاگ را می‌زنی پیام «لطفا توکن را وارد کنید» می‌بینی.

پس رفتار فعلی طبیعی است. برای ماندگار شدن توکن، باید داشبورد تغییر کند تا توکن را مثلاً در `localStorage` یا cookie ذخیره کند، یا یک فرم login واقعی داشته باشد که بعد از login توکن را خودش بگیرد و نگه دارد.

## آیا داشبورد ادمین نباید با username/password لاگین شود؟

در طراحی فعلی، نه. صفحه `/admin` فقط UI است و خودش login انجام نمی‌دهد. احراز هویت فقط هنگام call کردن APIهای محافظت‌شده انجام می‌شود.

یعنی الان باید این کار را انجام بدهی:

1. توکن را از `/token` بگیری.
2. توکن را در input داشبورد paste کنی.
3. دکمه ذخیره را بزنی.
4. تا وقتی صفحه refresh نشده، دکمه‌های رفرش لاگ و بروزرسانی پارامتر کار می‌کنند.

اگر صفحه refresh شود، باید دوباره توکن را وارد کنی.

## دریافت توکن

نمونه با `curl`:

```bash
curl -X POST \
  -F "username=admin" \
  -F "password=admin" \
  http://127.0.0.1:8000/token
```

خروجی شبیه این است:

```json
{
  "access_token": "eyJ...",
  "token_type": "bearer"
}
```

مقدار `access_token` را باید در داشبورد یا در تنظیمات اکسپرت به عنوان توکن قرار بدهی.

## ارتباط اکسپرت GridHedgeEA.mq5 با FastAPI

در اکسپرت این ورودی‌ها اضافه شده‌اند:

```mql5
input bool   EnableServerSync = true;
input string ServerURL        = "http://127.0.0.1:8000";
input string UserToken        = "";
input int    LogSyncInterval  = 60;
```

رفتار فعلی اکسپرت:

- اگر `EnableServerSync=false` باشد، هیچ درخواستی به سرور ارسال نمی‌شود.
- اگر `UserToken` خالی باشد، هیچ درخواستی به سرور ارسال نمی‌شود.
- برای ارسال لاگ، اکسپرت به `POST /logs` درخواست می‌زند.
- برای ثبت پارامتر، اکسپرت به `PUT /params/{name}` درخواست می‌زند.
- برای دریافت پارامتر، تابع `FetchParamFromServer()` از `GET /params` استفاده می‌کند.

نمونه payload ارسال لاگ:

```json
{
  "level": "INFO",
  "message": "Grid started | Symbol: EURUSD | LotSize: 0.010"
}
```

نمونه payload بروزرسانی پارامتر:

```json
{
  "name": "LotSize",
  "value": "0.010"
}
```

تمام درخواست‌های اکسپرت به endpointهای محافظت‌شده باید این header را داشته باشند:

```text
Authorization: Bearer <UserToken>
Content-Type: application/json
```

## تنظیمات لازم در MetaTrader 5

برای اینکه `WebRequest` در اکسپرت کار کند:

1. در MT5 برو به `Tools > Options > Expert Advisors`.
2. گزینه `Allow WebRequest for listed URL` را فعال کن.
3. آدرس سرور را اضافه کن، مثلاً:

```text
http://127.0.0.1:8000
```

اگر این کار انجام نشود، اکسپرت نمی‌تواند به FastAPI درخواست بفرستد.

## خطاهای رایج

`لطفا توکن را وارد کنید` در داشبورد:

توکن فقط در حافظه صفحه ذخیره شده و بعد از refresh پاک شده است. دوباره توکن را وارد کن.

`401 Unauthorized`:

توکن اشتباه، منقضی، یا با `SECRET_KEY` متفاوت ساخته شده است. اگر `SECRET_KEY` را تغییر دادی، باید توکن جدید بگیری.

`422 Unprocessable Entity`:

payload ارسالی با schema سرور جور نیست. برای `/logs` باید `message` وجود داشته باشد. برای `/params/{name}` باید `name` و `value` ارسال شود.

خطای `WebRequest` در MT5:

آدرس سرور را در تنظیمات `Allow WebRequest` اضافه کن و مطمئن شو `ServerURL` دقیقاً با همان آدرس شروع می‌شود.

`status=1001` یا لاگ قدیمی `http=1001` در اکسپرت:

این مقدار HTTP status واقعی FastAPI نیست. یعنی درخواست احتمالاً قبل از رسیدن به FastAPI در لایه `WebRequest`/شبکه MT5 شکست خورده است. موارد زیر را چک کن:

- سرور FastAPI واقعاً روشن باشد و از همان ماشین قابل دسترسی باشد.
- در مرورگر همان سیستم این آدرس باز شود: `http://127.0.0.1:8000/admin`
- در MT5 مسیر `Tools > Options > Expert Advisors`، آدرس `http://127.0.0.1:8000` در لیست WebRequest مجاز باشد.
- اگر MT5 داخل Wine، VPS، VM یا کانتینر اجرا می‌شود، `127.0.0.1` ممکن است به همان محیط MT5 اشاره کند، نه به سیستم میزبان FastAPI. در این حالت به جای `127.0.0.1` از IP واقعی ماشینی که FastAPI روی آن اجراست استفاده کن.
- اگر `ServerURL` را عوض کردی، همان آدرس جدید را هم در لیست مجاز MT5 اضافه کن.

`err=4006` کنار response خالی:

کد 4006 در MQL5 یعنی مشکل آرایه نامعتبر. در نسخه‌های قبلی لاگ‌گیری، اگر response خالی بود، تبدیل response به string می‌توانست همین خطا را ایجاد کند و خطای واقعی WebRequest را بپوشاند. در نسخه اصلاح‌شده، خطای WebRequest بلافاصله بعد از درخواست ذخیره و چاپ می‌شود.

## نکات امنیتی

- مقدار `SECRET_KEY` را در محیط واقعی حتماً تغییر بده.
- username/password پیش‌فرض `admin/admin` فقط برای تست مناسب است.
- JWT فعلی 7 روز اعتبار دارد.
- داشبورد فعلی توکن را دائمی ذخیره نمی‌کند و login واقعی ندارد.
