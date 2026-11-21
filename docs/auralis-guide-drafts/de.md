# Auralis Download Manager — Funktionshandbuch (Entwurf)

Entwurf für die nächste Version: Funktionen vor der Veröffentlichung anhand der Versionshinweise prüfen.

- **Installation:** Windows-x64-Version aus den [Releases](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) installieren. Unter **Settings → Browser Integration** **Set up everything** ausführen und die Erweiterung im Browser installieren.
- **Downloads:** Mit **Add URL** eine HTTP-, HTTPS- oder FTP-Adresse eingeben und das Ziel auswählen. Unterstützte Links lassen sich auch über die Erweiterung senden. Das Downloadfenster zeigt Fortschritt, Verbindungen und Geschwindigkeit.
- **Fortsetzen:** **Pause** und **Resume** verwenden. Bei abgelaufenem Link den Download anhalten und mit **Refresh download address** einen neuen Link auf dieselbe Datei eingeben. Die Fortsetzung hängt vom Server ab. Normale Segmente werden schon während des Downloads in eine temporäre Datei geschrieben; Schreiben und Prüfen am Ende können dauern.
- **Warteschlangen und Tempo:** Dateien markieren und **Add to queue** wählen. Zeiten im **Scheduler**, das Limit einer Datei im **Speed Limiter** einstellen.
- **Video und Audio:** Nach Einrichtung der Erweiterung und von yt-dlp eine unterstützte Videoseite öffnen und Qualität sowie Untertitel wählen. Größen erscheinen nur, wenn verfügbar; manche Formate benötigen FFmpeg zum Zusammenfügen von Video und Audio.
- **Torrents:** Mit **Add Torrent** eine `.torrent`-Datei öffnen oder einen Magnet-Link einfügen, Dateien und Ziel prüfen. Die Verfügbarkeit hängt von den Peers ab.
- **Darstellung:** Unter **Settings → Appearance** Farben und Material wählen; unter **Indicators** Fortschritt, Verbindungen und Diagramm getrennt einstellen. Mit **Export editable material** ein JSON-Material exportieren, bearbeiten und mit **Import material** importieren. Siehe [Format](../auralis-material-format.md).
- **Einstellungen sichern:** Unter **Settings → General → Preferences backup** **Save backup** und **Restore backup** nutzen. Enthalten sind Einstellungen und Materialien, nicht aber heruntergeladene oder teilweise Dateien, Verlauf, Passwörter oder Cookies. Pfade auf einem anderen PC prüfen.
- **Start und Updates:** Windows-Start unter **Settings → General**, Update-Hinweise unter **Advanced → Updates** einstellen.

Lokale Hashes erkennen spätere Änderungen, beweisen aber nicht allein die Echtheit der ursprünglichen Daten. Die Suche nach alternativen Torrents und Bereichsreparatur sind noch in Entwicklung.
