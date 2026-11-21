# Guide d’Auralis Download Manager — brouillon

Brouillon pour la prochaine version : vérifiez les fonctions dans ses notes avant publication.

- **Installation :** installez la version Windows x64 depuis les [versions](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest). Dans **Settings → Browser Integration**, choisissez **Set up everything**, puis installez l’extension dans le navigateur.
- **Téléchargements :** cliquez sur **Add URL**, saisissez une adresse HTTP, HTTPS ou FTP et choisissez la destination. L’extension peut aussi envoyer les liens compatibles. Ouvrez un téléchargement pour voir sa progression, ses connexions et sa vitesse.
- **Reprise :** utilisez **Pause** et **Resume**. Si le lien a expiré, arrêtez le téléchargement puis utilisez **Refresh download address** avec un nouveau lien vers le même fichier. La reprise dépend du serveur. Les segments ordinaires sont écrits pendant le téléchargement dans un seul fichier temporaire ; l’écriture finale et la vérification peuvent prendre du temps.
- **Files et vitesse :** sélectionnez les fichiers puis **Add to queue**. Utilisez **Scheduler** pour les horaires et **Speed Limiter** pour limiter un téléchargement.
- **Vidéo et audio :** après configuration de l’extension et de yt-dlp, ouvrez une page compatible et choisissez la qualité et les sous-titres. Les tailles ne sont affichées que si elles sont disponibles ; certains formats nécessitent FFmpeg pour réunir la vidéo et l’audio.
- **Torrents :** utilisez **Add Torrent** pour ouvrir un fichier `.torrent` ou coller un lien magnet, puis vérifiez les fichiers et la destination. La disponibilité dépend des pairs.
- **Apparence :** dans **Settings → Appearance**, choisissez couleurs et matériau ; dans **Indicators**, réglez séparément la barre, les connexions et le graphique. Exportez un matériau JSON avec **Export editable material**, modifiez-le, puis utilisez **Import material**. Voir le [format](../auralis-material-format.md).
- **Sauvegarde des préférences :** dans **Settings → General → Preferences backup**, utilisez **Save backup** et **Restore backup**. Elle comprend préférences et matériaux, mais pas fichiers téléchargés, téléchargements partiels, historique, mots de passe ou cookies. Vérifiez les chemins sur un autre PC.
- **Démarrage et mises à jour :** réglez le démarrage Windows dans **Settings → General** et les notifications dans **Advanced → Updates**.

Les empreintes locales détectent les modifications ultérieures, mais ne prouvent pas à elles seules l’authenticité des données. La recherche de torrents alternatifs et la réparation de plages sont encore en développement.
