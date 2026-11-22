# Guia do Auralis Download Manager — rascunho

Rascunho para a próxima versão: confirme os recursos nas notas da versão antes da publicação.

- **Instalação:** instale a versão Windows x64 pela página de [lançamentos](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest). Em **Settings → Browser Integration**, use **Set up everything** e instale a extensão no navegador.
- **Downloads:** clique em **Add URL**, informe um endereço HTTP, HTTPS ou FTP e escolha o destino. A extensão também envia links compatíveis. Abra um download para ver o progresso, as conexões e a velocidade.
- **Retomar:** use **Pause** e **Resume**. Se o link expirar, pause e use **Refresh download address** com outro endereço do mesmo arquivo. A retomada depende do servidor. Segmentos comuns são gravados durante o download em um único arquivo temporário; a gravação final e a verificação ainda podem levar tempo.
- **Filas e velocidade:** selecione os arquivos e use **Add to queue**. Configure horários no **Scheduler** e limite um download em **Speed Limiter**.
- **Vídeo e áudio:** com a extensão e o yt-dlp configurados, abra uma página compatível e escolha a qualidade e as legendas. Os tamanhos aparecem quando disponíveis; alguns formatos exigem FFmpeg para unir vídeo e áudio.
- **Torrents:** use **Add Torrent**, abra um arquivo `.torrent` ou cole um link magnet e confira os arquivos e o destino. A disponibilidade depende dos participantes.
- **Aparência:** em **Settings → Appearance**, escolha cores e material; em **Indicators**, ajuste separadamente barra, conexões e gráfico. Exporte um material JSON em **Export current theme…**, edite-o e use **Import theme…**. Veja o [formato](../auralis-material-format.md).
- Antes de fazer backup ou restaurar downloads, pare as transferências, as verificações e as filas. Em **Settings → General → Download backup**, use **Back up downloads…** para guardar preferências, histórico, filas, arquivos compatíveis e progresso salvo. Na nova instalação, use **Restore downloads…** e selecione o arquivo de backup e a pasta de destino. **Preferences backup** permite salvar apenas as configurações em JSON. Senhas e cookies ficam de fora.
- **Inicialização e atualizações:** configure a inicialização com o Windows em **Settings → General** e os avisos em **Advanced → Updates**.

Hashes locais detectam alterações posteriores, mas não provam sozinhos que os dados originais são autênticos. Na janela do download, **Check saved data** verifica blocos com hashes salvos; **Check source and repair** prepara o reparo se o servidor HTTP for compatível.

Na próxima versão para Windows, ative a recuperação automática em **Settings → Torrents**. Quando um download direto elegível esgota as tentativas, o Auralis pesquisa no Internet Archive com palavras do nome do arquivo. Escolha revisar a correspondência antes de continuar ou autorize a continuação automática se houver uma única correspondência, pelo menos duas peças salvas verificadas e todas as verificações de candidatos forem concluídas. Downloads privados e downloads com uma soma de verificação esperada para o arquivo inteiro ficam de fora.

Na janela de download, **Find a torrent for recovery** também permite verificar um arquivo torrent local, um link magnet ou uma URL HTTP(S) pública de um torrent. O Auralis copia as peças verificadas para uma nova pasta, preserva o arquivo parcial original e baixa as peças restantes de pares do BitTorrent. A janela exibe os detalhes e a lista marca os downloads recuperados com **Direct → Torrent**.
