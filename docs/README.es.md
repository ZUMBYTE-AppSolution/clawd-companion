<p align="center"><img src="media/app-icon.png" width="104" height="104" alt="Claw’d Companion"></p>

# Claw’d Companion

[Deutsch](../README.md) · [English](README.en.md) · [简体中文](README.zh-Hans.md) · [हिन्दी](README.hi.md) · **Español** · [العربية](README.ar.md) · [Français](README.fr.md) · [বাংলা](README.bn.md) · [Português](README.pt.md) · [Bahasa Indonesia](README.id.md) · [اردو](README.ur.md)

Un cangrejo de píxeles para tu escritorio. Claw’d levanta la vista del portátil cuando Claude necesita tu atención, sigue el cursor con los ojos y busca una ventana donde sentarse entre respuestas.

[**Última versión**](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/latest) · macOS · Windows · Linux · [Zumbyte · AppSolution](https://zumbyte.de/)

## Arena sin fin

Claw’d prefiere descansar entre 45 y 100 segundos en una barra de título libre. Si mueves la ventana, se mueve con ella. En Wayland dispone de una repisa en su propia ventana.

Elige Claro, Oscuro o Seguir el sistema en **Overlay → Apariencia**. El cambio se aplica al instante y se conserva al reiniciar. En Linux, la ventana de Wayland, las pestañas, los menús y los campos usan colores coordinados.

Abre la arena maximizada desde Récords. Muévete con WASD o las flechas. Claw’d dispara automáticamente. Cada nivel tiene cuatro oleadas y un jefe.

Empiezas con tres vidas y ganas otra cada dos niveles completados. Combina disparos perforantes, múltiples y explosivos. Tu mejor nivel y oleada se guardan en este dispositivo.

<p><img width="47%" alt="Claw’d · ☀" src="https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/latest/download/Clawd-Linux-light.png"> <img width="47%" alt="Claw’d · ☾" src="https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/latest/download/Clawd-Linux-dark.png"></p>

## La aplicación por dentro

![Compañero](media/app-overview.png)

| Ajustes de la superposición | Conexiones |
| --- | --- |
| ![Ajustes de la superposición](media/app-settings.png) | ![Conexiones](media/app-claude.png) |

| Información y actualizaciones | Récords y cuentas de la arena |
| --- | --- |
| ![Información y actualizaciones](media/app-updates.png) | ![Récords y cuentas de la arena](media/app-highscores.png) |


La captura del panel de actualizaciones se tomó sin consultar la red. La imagen de los récords muestra la clasificación nativa con una sesión local de prueba y puntuaciones de ejemplo.

Las capturas muestran la interfaz del Mac en inglés con datos de cuota de ejemplo. La consola del navegador es una recreación local. [↗](media/CAPTURES.md)

## Instalación

En macOS 13 o posterior, abre el DMG o descomprime el ZIP y arrastra Clawd Companion a Aplicaciones. Ambas descargas contienen la misma aplicación, firmada con Developer ID y notarizada por Apple. En Windows x64, ejecuta el instalador o extrae el ZIP portátil antes de abrir el ejecutable. En Linux x86-64 puedes usar un DEB, un RPM o el archivo tar. La página de la versión muestra los archivos publicados para cada plataforma.

La versión para Mac admite chips de Apple e Intel. Los ejemplos de ventanas, permisos y conexiones con Claude Code corresponden a la aplicación nativa para Mac. En Linux, la integración también depende del sistema de ventanas.

Windows y Linux usan Qt. En Windows y X11, Claw’d puede leer la posición de la ventana activa y fijarse a ella. El anclaje a ventanas no está disponible en Wayland. Allí la detección de inactividad usa GNOME IdleMonitor si está disponible. Si no hay señal de inactividad, la arena espera a que permitas el juego durante el uso activo.

| OS | Instalación |
| --- | --- |
| macOS | DMG · ZIP |
| Windows x64 | Setup · Portable ZIP |
| Linux x86-64 | DEB · RPM · tar.gz |

[SHA256SUMS](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/latest/download/SHA256SUMS) · [Última versión](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/latest)

**macOS · Homebrew**

```sh
brew tap zumbyte/clawd https://github.com/ZUMBYTE-AppSolution/clawd-companion
brew install --cask zumbyte/clawd/clawd-companion
```

**Actualizar con Homebrew**

```sh
brew update
brew upgrade --cask zumbyte/clawd/clawd-companion
```

**Debian / Ubuntu**

```sh
sudo apt install ./clawd-companion_*_amd64.deb
```

**Fedora / RHEL**

```sh
sudo dnf install ./clawd-companion-*-1.x86_64.rpm
```

## Cuando Claude está trabajando

| Evento visible | Reacción de Claw’d |
| --- | --- |
| Claude escribe o edita | Teclea en su pequeño portátil. |
| Planificación, búsqueda o lectura | Traza un plan en el rotafolio, investiga con la lupa o abre una carpeta. |
| Ejecución de código o creación de un artefacto | Trabaja en una terminal diminuta o dibuja en el caballete. |
| Una herramienta pide permiso | Despliega un cartel «OK?» hasta que se resuelva la solicitud. Respóndele en Claude. |
| Claude Code informa de subagentes | Hace malabares con figuritas de agentes. El estado muestra el número real. |
| Termina una respuesta o aparece una advertencia | Desciende por una cuerda para celebrar o muestra el aviso en un bocadillo de píxeles. |

## Conectar Claude Desktop (macOS)

1. Abre **Conexiones** en Claw’d y activa la conexión con **Claude Desktop**.
2. Selecciona **Permitir acceso…**. En macOS, abre **Ajustes del Sistema → Privacidad y seguridad → Accesibilidad** y activa **Claw’d Companion**.
3. En la **aplicación Claude** del Mac, abre **Configuración → Uso** y deja la página abierta unos instantes. Elige **Leer ahora** en Claw’d para volver a comprobarla.

También puedes abrir el menú **Uso** junto al cuadro de mensaje de Claude. Con el menú abierto, Claw’d puede leer los períodos que aparecen. Cuando está cerrado, el botón solo aporta el período indicado en su etiqueta, como el límite semanal.

Claw’d lee el porcentaje restante de la sesión o de la semana y la hora de reinicio cuando Claude los muestra en un formato compatible. Vuelve a abrir la vista de uso si necesitas una lectura actualizada.

Al activar la conexión, **Claude Desktop** pasa a ser la fuente de la cuota. La última lectura válida conserva su fecha y hora originales. Si después eliges otra fuente en **Compañero → Límites de uso**, Claw’d recuerda tu elección al reiniciarse.

[Apple](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) · [Claude](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset)

## Conectar Claude.ai

Activa la conexión del navegador en Conexiones. En Chrome, Edge o Brave, activa el modo de desarrollador, elige Cargar descomprimida y selecciona la carpeta BrowserExtension incluida. Pega el código de emparejamiento en la ventana de la extensión y recarga la pestaña de Claude.ai. La app de Mac también incluye una extensión de Safari. Actívala y permite el acceso a claude.ai.

Abre la página de uso en el navegador emparejado. Si Claude muestra un límite de sesión o semanal, Claw’d puede mostrar el porcentaje restante, el momento de reinicio y la última lectura. Los tiempos relativos son aproximados. Los datos ausentes o caducados quedan en blanco. La extensión transmite por conexión local la actividad y los avisos visibles en las pestañas abiertas.

[Claude.ai](https://claude.ai/settings/usage) · [Safari](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)

### Prueba un bocadillo desde la consola del navegador

Este ejemplo añade un aviso temporal a la pestaña de Claude.ai emparejada. La extensión envía su texto a Claw’d. Es una demostración local. La secuencia del navegador que se muestra también emplea eventos simulados.

```js
(() => {
  const notice = document.createElement("div");
  notice.setAttribute("role", "alert");
  notice.textContent = "Claw’d pixel bubble test";
  Object.assign(notice.style, {
    position: "fixed", top: "1rem", right: "1rem", zIndex: "2147483647",
    background: "#fff", color: "#222", padding: "0.75rem"
  });
  document.body.append(notice);
  setTimeout(() => notice.remove(), 4000);
})();
```

![Prueba un bocadillo desde la consola del navegador](media/browser-bridge-demo.gif)

**Claude.ai → Claw’d · JSON**

```jsonl
{"type":"activity","state":"planning"}
{"type":"activity","state":"executing"}
{"type":"activity","state":"done"}
```

## Paseos por las ventanas, juegos con el cursor y arena de virus

En Mac, arrastra a Claw’d a una ventana, pulsa el botón derecho y elige Pin to Window. Conserva su sitio al mover la ventana y puede bajar por la cuerda. Al pasear, trepa hasta las barras de título, mira alrededor, parpadea y salta. Sus ojos siguen el puntero. El lanzaletras vuelve a apuntar en cada disparo de una ráfaga aleatoria de 3 a 42. El contador registra el contacto con un proyectil visible.

En Mac, una ronda automática de escritorio puede empezar tras un mínimo de 90 segundos sin actividad. Claw’d tiene 100 puntos de vida. Dos oleadas aleatorias preceden al jefe final. Vigila las barras de vida y recoge curación, escudos o fuego rápido. Al usar el ratón o el teclado, la partida se pausa. Permite jugar mientras usas el equipo para ayudar con clics. Si pierde, una lápida con GIT marca el sitio durante cinco minutos reales antes de que salga de la tierra. La música y los efectos se pueden activar por separado.

En los ajustes de la superposición puedes elegir el idioma, reducir el movimiento y cambiar el volumen. Cada sonido se silencia por separado. Los avisos de Claude.ai conservan su texto original.

## Récords y cuentas de la arena

En Récords aparecen tus puntos locales, bajas, muertes, proporción de bajas y muertes y victorias. Una ronda terminada cuenta si has alcanzado a un enemigo o recogido un potenciador efectivo. Para entrar en la clasificación en línea, crea una cuenta de arena independiente con nombre de usuario, correo y contraseña e inicia sesión en la aplicación. Tú inicias cada ronda puntuable. El servidor confirma las acciones y calcula el resultado. La clasificación muestra tu nombre y estadísticas. Tu correo es privado. El juego en línea requiere conexión con el servidor.

## Galería de animaciones

| Expresiones y juegos | Movimiento por ventanas |
| --- | --- |
| ![Expresiones y juegos](media/poses-idle.gif) | ![Movimiento por ventanas](media/poses-movement.gif) |

| Herramientas y permisos de Claude | Combate, tumba y resurrección |
| --- | --- |
| ![Herramientas y permisos de Claude](media/poses-work.gif) | ![Combate, tumba y resurrección](media/poses-arcade.gif) |

![Paseos por las ventanas, juegos con el cursor y arena de virus](media/virus-arena.gif)

▶ [Ver la arena con sonido. El vídeo acorta los cinco minutos junto a la tumba.](media/virus-arena.mp4)

## Actualizaciones y desarrollo local

La aplicación consulta las versiones de GitHub al arrancar y después una vez al día. El aviso de una nueva versión lleva a sus cambios y a la descarga para tu sistema.

En Información y actualizaciones puedes buscar una versión y elegir un paquete. Instálalo siguiendo las instrucciones anteriores. En Conexiones de la app de Mac puedes activar por separado la actividad de Claude Code y los datos de cuota. Abre una nueva sesión de Claude Code tras configurarlo. El navegador y la terminal mantienen sus propias lecturas.

La aplicación para Mac usa Swift y AppKit. Instala Xcode y compila desde la raíz del repositorio. Las pruebas de JavaScript emplean datos locales. El cliente de escritorio portátil se encuentra en Desktop.

```sh
./Scripts/build-mac.sh
swift test
node --test BrowserTests/*.test.js
python3 Scripts/test-hooks.py
```

[Swift](../Package.swift) · [Desktop](../Desktop/) · [Claude Code](https://code.claude.com/docs/en/hooks) · [Status line](https://code.claude.com/docs/en/statusline)

[Windows](../Scripts/package-windows.ps1) · [Linux](../Scripts/package-linux.sh)

## Estudio y comunidad

Andreas Zumbansen dirige Zumbyte · AppSolution en Kamen, Alemania. Este estudio independiente crea aplicaciones móviles y de escritorio y desarrolla software a medida para empresas y equipos.

Zumbyte · AppSolution · Kastanienallee 16a · 59174 Kamen · DE · +49 177 4149667

[Zumbyte](https://zumbyte.de/) · [Aviso legal](https://zumbyte.de/impressum/) · [info@zumbyte.de](mailto:info@zumbyte.de)

Un abrazo a toda la comunidad que programa con IA. ¡Gracias por crear, compartir y ayudaros mutuamente!
