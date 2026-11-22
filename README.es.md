# Auralis Download Manager

[English](README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt-BR.md) · [简体中文](README.zh-CN.md)

Auralis es un gestor de descargas gratuito para Windows x64 con interfaz de estilo cristal, controles detallados y extensión de navegador. Es una bifurcación independiente GPL-3.0 de [Mister Download Manager](https://github.com/anefzaoui/misterdownloadmanager), no una versión oficial.

[Descargar la última versión para Windows](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [Extensiones de navegador](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [Notas de las versiones](CHANGELOG.md)

## Auralis en Windows

Capturas parciales de una sesión real de Auralis 0.3.49; la grabación recortó los bordes derecho e inferior. Debajo hay imágenes de ejemplo anteriores.

![Lista de descargas (vista parcial)](docs/images/auralis/current-main-partial.png)

![Apariencia e indicadores de conexión (vista parcial)](docs/images/auralis/current-settings-partial.png)

![Fragmento de la grabación (vista parcial)](docs/images/auralis/current-recording-excerpt.gif)

## Capturas

Las imágenes muestran la interfaz con descargas de ejemplo. La apariencia, los materiales y los colores se pueden configurar.

| Biblioteca de descargas | Descarga actual |
| --- | --- |
| ![Biblioteca de descargas](docs/images/auralis/main.png) | ![Descarga actual](docs/images/auralis/download.png) |

| Apariencia e indicadores | Información del archivo |
| --- | --- |
| ![Apariencia e indicadores](docs/images/auralis/settings.png) | ![Información del archivo](docs/images/auralis/file-info.png) |

![Descarga finalizada](docs/images/auralis/complete.png)

### Indicadores líquidos

Elige por separado los materiales, colores y formas del progreso, las conexiones y la gráfica. Los estilos líquidos animan el llenado, las gotas y las ondas; los estados proceden del gestor de descargas.

![Animación de progreso, conexiones y gráfica](docs/images/auralis/liquid-flow.gif)

## Funciones

- Descargas con varias conexiones, pausa y reanudación, colas, límites de velocidad y gráfica en directo.
- Extensión para enviar descargas y enlaces multimedia compatibles. Hay paquetes para Chromium y Firefox en los archivos de la versión; requieren instalación y permisos.
- Ventanas independientes de descarga, información, finalización y ajustes, con materiales, colores e indicadores configurables.
- Controles de bandeja, inicio opcional con Windows e icono separado para descargas ocultas.
- Consulta de calidades de vídeo y audio con yt-dlp, con sesión del navegador o archivo de cookies cuando el sitio lo permite.
- Avisos y actualizaciones en la aplicación, y copia y restauración de preferencias.
- El motor funciona dentro de Auralis; un pequeño asistente nativo comunica el navegador con la aplicación.
- Añade enlaces HTTP, HTTPS o FTP o envíalos desde el navegador; la ventana muestra velocidad, conexiones y tiempo restante. La reanudación depende del origen, y el vaciado del disco o la verificación pueden tardar.
- Se pueden usar sumas completas proporcionadas por el servidor. Añade un torrent o magnet, revisa archivos y destino, y vuelve a comprobar las piezas con sus hashes. Algunas combinaciones de audio y vídeo requieren FFmpeg.
- La exportación del tema incluye paleta, material, tipografía e indicadores, pero no los archivos de fondo. Consulta el [formato de temas](docs/auralis-theme-format.md).

La copia de preferencias excluye contraseñas, credenciales y cookies; puede ser necesario volver a iniciar sesión. Las restricciones del navegador y del sitio pueden afectar a la búsqueda de vídeo.

## Guías y recuperación

Consulta las [guías de uso](docs/auralis-guide-drafts/es.md), disponibles en varios idiomas y en proceso de actualización.

Las descargas ordinarias segmentadas escriben los bytes en sus posiciones dentro de un único archivo temporal. La comprobación detecta cambios en bloques con huellas guardadas; reparar requiere un servidor compatible y no puede forzar el soporte de rangos. Se puede comparar un torrent o magnet, o buscar en Internet Archive, para recuperar una descarga detenida. Las piezas coincidentes no prueban el resto; se necesitan pares y se conserva el archivo parcial original. La recuperación automática sigue en desarrollo.

Exporta e importa temas JSON editables con los indicadores. La copia de preferencias aún no incluye archivos descargados, parciales ni historial; se está desarrollando una copia completa.

## Instalación

Descarga y ejecuta el instalador de Windows x64 desde la [última versión](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest). Instala la extensión correspondiente y sigue **Configuración → Integración del navegador**.

## Licencia y atribución

Auralis se distribuye bajo [GNU GPL v3](LICENSE). Es una bifurcación de Mister Download Manager de Ahmed Nefzaoui y colaboradores; consulta [atribución](ATTRIBUTION.md) y el [proyecto original](https://github.com/anefzaoui/misterdownloadmanager).
