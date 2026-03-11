# Tenant Health Check

Genererar en **HTML‑rapport för Microsoft 365‑tenantens säkerhets‑ och hälsostatus** via Microsoft Graph (app‑only).

Rapporten är tänkt som ett **alternativ till Power Automate** när:
- cross‑tenant‑export behövs
- du vill köra lokalt / schemalagt
- du vill ha full kontroll på output

---

## ✨ Vad ingår i rapporten

- Tenant‑rubrik: **DisplayName (defaultDomain)**
- Service Health (KPI‑vy)
- Secure Score (KPI)
- Security Alerts
- Sign‑in risk
- Top Actions
- Not Implemented / Partially Implemented kontroller

Output är en **fristående HTML‑fil** som kan öppnas i valfri webbläsare.

---

## 📂 Repo‑innehåll

- `TenantHealthReport.ps1`  
  Huvudscriptet som genererar HTML‑rapporten

- `Create-AppRegistration.ps1`  
  Skapar App registration + Graph‑permissions automatiskt

- `HowTo.md`  
  Fullständig runbook (förkrav, permissions, felsökning)

- `.gitignore`  
  Skyddar mot att HTML‑output och secrets committas

---

## 🚀 Snabbstart

1) Skapa App registration (en gång)

###
./Create-AppRegistration.ps1
###

2) Kör rapporten

###
./TenantHealthReport.ps1   -TenantId "<TENANT-ID>"   -ClientId "<CLIENT-ID>"   -ClientSecret "<CLIENT-SECRET>"
###

3) Öppna genererad HTML‑fil i webbläsaren

---

## 📖 Dokumentation

Se **HowTo.md** för:
- detaljerade prerequisites
- exakta Graph‑permissions
- tenant‑namn‑logik
- vanliga fel (403, tomma tabeller m.m.)
- säkerhetsaspekter

README hålls medvetet kort – **HowTo.md är facit**.

---

## 🔐 Säkerhet

- Endast **read‑only Graph‑permissions**
- Ingen data skrivs tillbaka till tenant
- Client Secret ska **aldrig** committas
- HTML‑output ignoreras via `.gitignore`

---

## 🛠️ Rekommenderade vidare steg

- Köra via **Azure Automation Runbook**
- Schemalägga via **cron / Task Scheduler**
- Ladda upp HTML till **SharePoint**
- Skicka rapporten via **mail**

---

## ✅ Status

✔️ Produktionsklar  
✔️ Tenant‑agnostisk  
✔️ Testad mot Microsoft Graph v1.0
