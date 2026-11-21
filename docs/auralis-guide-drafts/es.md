# Guía de Auralis Download Manager — borrador

Borrador para la próxima versión: confirme las funciones en las notas de la versión antes de publicarlo.

- **Instalación:** instale la versión Windows x64 desde [Releases](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest). En **Settings → Browser Integration**, use **Set up everything** e instale la extensión en el navegador.
- **Descargas:** pulse **Add URL**, introduzca una dirección HTTP, HTTPS o FTP y elija el destino. La extensión también puede enviar enlaces compatibles. Abra una descarga para ver el progreso, las conexiones y la velocidad.
- **Reanudar:** use **Pause** y **Resume**. Si caducó el enlace, pause y use **Refresh download address** con otro enlace al mismo archivo. La reanudación depende del servidor. Los segmentos normales se escriben durante la descarga en un solo archivo temporal; el guardado y la verificación final pueden tardar.
- **Colas y velocidad:** seleccione archivos y use **Add to queue**. Configure horarios con **Scheduler** y límites de un archivo en **Speed Limiter**.
- **Vídeo y audio:** con la extensión y yt-dlp configurados, abra un vídeo compatible y elija calidad y subtítulos. Los tamaños solo aparecen cuando están disponibles; algunos formatos necesitan FFmpeg para unir audio y vídeo.
- **Torrents:** use **Add Torrent**, abra un archivo `.torrent` o pegue un enlace magnet, revise los archivos y el destino. La disponibilidad depende de los pares.
- **Apariencia:** en **Settings → Appearance**, elija colores y material; en **Indicators**, ajuste por separado barra, conexiones y gráfico. Exporte y edite un material JSON con **Export editable material** e impórtelo con **Import material**. Consulte el [formato](../auralis-material-format.md).
- **Copia de preferencias:** en **Settings → General → Preferences backup**, use **Save backup** y **Restore backup**. Incluye preferencias y materiales, no archivos descargados, descargas parciales, historial, contraseñas ni cookies. Compruebe las rutas en otro equipo.
- **Inicio y actualizaciones:** configure el inicio con Windows en **Settings → General** y las notificaciones en **Advanced → Updates**.

Los hashes locales detectan cambios posteriores, pero no prueban por sí solos la autenticidad de los datos. La búsqueda de torrents alternativos y la reparación de rangos aún están en desarrollo.
