# Guía de Auralis Download Manager — borrador

Borrador para la próxima versión: confirme las funciones en las notas de la versión antes de publicarlo.

- **Instalación:** instale la versión Windows x64 desde [Releases](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest). En **Settings → Browser Integration**, use **Set up everything** e instale la extensión en el navegador.
- **Descargas:** pulse **Add URL**, introduzca una dirección HTTP, HTTPS o FTP y elija el destino. La extensión también puede enviar enlaces compatibles. Abra una descarga para ver el progreso, las conexiones y la velocidad.
- **Reanudar:** use **Pause** y **Resume**. Si caducó el enlace, pause y use **Refresh download address** con otro enlace al mismo archivo. La reanudación depende del servidor. Los segmentos normales se escriben durante la descarga en un solo archivo temporal; el guardado y la verificación final pueden tardar.
- **Colas y velocidad:** seleccione archivos y use **Add to queue**. Configure horarios con **Scheduler** y límites de un archivo en **Speed Limiter**.
- **Vídeo y audio:** con la extensión y yt-dlp configurados, abra un vídeo compatible y elija calidad y subtítulos. Los tamaños solo aparecen cuando están disponibles; algunos formatos necesitan FFmpeg para unir audio y vídeo.
- **Torrents:** use **Add Torrent**, abra un archivo `.torrent` o pegue un enlace magnet, revise los archivos y el destino. La disponibilidad depende de los pares.
- **Apariencia:** en **Settings → Appearance**, elija colores y material; en **Indicators**, ajuste por separado barra, conexiones y gráfico. Exporte y edite un material JSON con **Export current theme…** e impórtelo con **Import theme…**. Consulte el [formato](../auralis-material-format.md).
- Para copiar o restaurar las descargas, detén las transferencias, las comprobaciones y las colas. Abre **Settings → General → Download backup** y elige **Back up downloads…** para guardar las preferencias, el historial, las colas, los archivos compatibles y el progreso guardado. En la nueva instalación, usa **Restore downloads…** y selecciona el archivo y la carpeta de destino. **Preferences backup** permite copiar solo los ajustes en JSON. Las copias excluyen contraseñas y cookies.
- **Inicio y actualizaciones:** configure el inicio con Windows en **Settings → General** y las notificaciones en **Advanced → Updates**.

Los hashes locales detectan cambios posteriores, pero no prueban por sí solos la autenticidad de los datos. En la ventana de descarga, **Check saved data** comprueba los bloques con hashes guardados; **Check source and repair** prepara la reparación si el servidor HTTP es compatible.

En la próxima versión para Windows, active la recuperación automática en **Settings → Torrents**. Cuando una descarga directa compatible agota sus reintentos, Auralis busca en Internet Archive usando palabras del nombre del archivo. Puede elegir si quiere revisar la coincidencia antes de continuar o permitir que Auralis continúe por su cuenta cuando hay una sola coincidencia, al menos dos piezas guardadas coinciden y todas las comprobaciones de candidatos se completan. Se excluyen las descargas privadas y las que tienen una suma de verificación prevista para todo el archivo.

En la ventana de descarga, **Find a torrent for recovery** también permite comprobar un archivo torrent local, un enlace magnet o un enlace HTTP(S) público a un torrent. Auralis copia las piezas verificadas en una carpeta nueva, conserva el archivo parcial original y descarga las piezas restantes de pares de BitTorrent. La ventana muestra los detalles y la lista identifica estas descargas con **Direct → Torrent**.
