# Guia do Auralis Download Manager — rascunho

Rascunho para a próxima versão: confirme os recursos nas notas da versão antes da publicação.

- **Instalação:** instale a versão Windows x64 pela página de [lançamentos](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest). Em **Settings → Browser Integration**, use **Set up everything** e instale a extensão no navegador.
- **Downloads:** clique em **Add URL**, informe um endereço HTTP, HTTPS ou FTP e escolha o destino. A extensão também envia links compatíveis. Abra um download para ver o progresso, as conexões e a velocidade.
- **Retomar:** use **Pause** e **Resume**. Se o link expirar, pause e use **Refresh download address** com outro endereço do mesmo arquivo. A retomada depende do servidor. Segmentos comuns são gravados durante o download em um único arquivo temporário; a gravação final e a verificação ainda podem levar tempo.
- **Filas e velocidade:** selecione os arquivos e use **Add to queue**. Configure horários no **Scheduler** e limite um download em **Speed Limiter**.
- **Vídeo e áudio:** com a extensão e o yt-dlp configurados, abra uma página compatível e escolha a qualidade e as legendas. Os tamanhos aparecem quando disponíveis; alguns formatos exigem FFmpeg para unir vídeo e áudio.
- **Torrents:** use **Add Torrent**, abra um arquivo `.torrent` ou cole um link magnet e confira os arquivos e o destino. A disponibilidade depende dos participantes.
- **Aparência:** em **Settings → Appearance**, escolha cores e material; em **Indicators**, ajuste separadamente barra, conexões e gráfico. Exporte um material JSON em **Export current theme…**, edite-o e use **Import theme…**. Veja o [formato](../auralis-material-format.md).
- **Backup de preferências:** em **Settings → General → Preferences backup**, use **Save backup** e **Restore backup**. A versão atual salva preferências e materiais, mas não arquivos baixados, downloads parciais, histórico, senhas ou cookies. Confira os caminhos em outro computador. Um backup completo dos arquivos está em desenvolvimento.
- **Inicialização e atualizações:** configure a inicialização com o Windows em **Settings → General** e os avisos em **Advanced → Updates**.

Hashes locais detectam alterações posteriores, mas não provam sozinhos que os dados originais são autênticos. Na janela do download, **Check saved data** verifica blocos com hashes salvos; **Check source and repair** prepara o reparo se o servidor HTTP for compatível. Em **Find a torrent for recovery**, pesquise no Internet Archive, escolha um torrent ou compare um magnet. A correspondência parcial não verifica o restante; a continuação usa participantes e preserva o arquivo parcial original. A recuperação automática e o backup completo ainda estão em desenvolvimento.
