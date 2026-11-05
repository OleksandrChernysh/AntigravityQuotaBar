# Antigravity Counter ♊ (macOS Menu Bar App)

Aplicación nativa para la barra de menús de macOS (Menu Bar / Status Bar) que muestra en tiempo real, junto al reloj de tu Mac, los porcentajes restantes de cuota de **Google Antigravity**:
- **Gemini 5-Hour Limit Remaining** (Ventana de 5 horas)
- **Gemini Weekly Limit Remaining** (Límite semanal)
- **Claude & GPT Models Quota** (Ventana de 5 horas y ciclo semanal)
- **Gemini 4 Argon Quota** (Nuevo modelo frontera con cuota semanal independiente)

---

## ✨ Características

- **Ultra ligero y nativo**: Escrito en Swift con Cocoa / AppKit (sin Electron, sin dependencias pesadas).
- **Directo a la fuente**: Detecta dinámicamente los daemons locales de Antigravity (`agy` o `language_server`) vía Connect-RPC en milisegundos con soporte HTTP/HTTPS y tokens CSRF.
- **Visualización en la barra**:
  - `♊ 5h: 78% (1h 28m) · Sem: 38% (2d 2h)` (o en 10 estilos configurables con o sin cuenta regresiva).
- **Menú interactivo desplegable**:
  - Agrupación dinámica de modelos: **Google Gemini**, **Claude and GPT**, y **Gemini 4 Argon**.
  - Indicadores de salud con emojis de colores (🟢 > 50%, 🟡 20-50%, 🔴 < 20%).
  - **Cuenta regresiva exacta de reset**: Muestra los días y horas restantes en cada métrica (ej. `⏳ 2d 2h`) y fecha/hora exacta (`Reset: en 2 días, 2 horas (sáb 7 nov, 01:31)`).
  - Botón de refresco manual (`⌘R`).
  - Frecuencia de actualización configurable (30s, 1m, 5m).
  - Opción de inicio automático al encender la Mac.
- **Carga instantánea en el arranque**: Guarda en caché local (`UserDefaults`) los últimos valores para mostrarlos de inmediato al reiniciar el equipo.

---

## 🛠️ Requisitos

- macOS 13.0 (Ventura) o posterior (probado en Apple Silicon M1/M2/M3/M4).
- Antigravity IDE instalado.
- Herramientas de línea de comandos de Xcode (`swiftc`).

---

## 🚀 Compilación e Instalación

1. Clona el repositorio:
   ```bash
   git clone https://github.com/alainjpdev/antigravityCounter.git
   cd antigravityCounter
   ```

2. Compila la aplicación:
   ```bash
   chmod +x GeminiQuotaBar/build.sh
   ./GeminiQuotaBar/build.sh
   ```

3. Instala la app en tu carpeta de Aplicaciones:
   ```bash
   cp -r GeminiQuotaBar/build/GeminiQuotaBar.app /Applications/
   open /Applications/GeminiQuotaBar.app
   ```

---

## 📄 Estructura del Proyecto

```text
├── GeminiQuotaBar/
│   ├── Sources/
│   │   ├── AppDelegate.swift    # Lógica de la barra de menú, interfaz y LaunchAgent
│   │   ├── QuotaFetcher.swift   # Detección de proceso y consulta Connect-RPC a Antigravity
│   │   └── main.swift           # Punto de entrada de la aplicación accesoria
│   └── build.sh                 # Script de compilación nativa y empaquetado .app
├── .gitignore
└── README.md
```
