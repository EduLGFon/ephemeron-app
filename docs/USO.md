# Manual do Usuário - Ephemeron

Documentação técnica: `docs/ARCHITECTURE.md`, `docs/PRIVACY.md`, `docs/SECURITY_REVIEW.md`.

## 1. Introdução

Ephemeron é um app de produtividade offline-first: calendário, tarefas, hábitos, contagens regressivas, foco, notas e listas em um único app rápido. Tudo funciona sem nenhuma conta. A sincronização (Google e conta de e-mail) é opcional.

Plataformas: Android (prioridade máxima), Linux e Web (médio), Windows (baixo), iOS e macOS (suportados).

## 2. Navegação e interface

- Sete seções: Calendário, Tarefas, Matriz, Hábitos, Contagens, Foco, Notas.
- Barra de navegação inferior com as 5 primeiras seções fixas e um botão "Mais" para as demais, Busca, Ajustes e "Personalizar navegação".
- Personalizar navegação: reordenar seções por arrasto; a ordem é salva.
- A última seção aberta é restaurada ao abrir o app.
- Botão flutuante (FAB) cria o item principal da seção atual.
- Busca global acessível pelo menu "Mais" (ícone de busca) ou em `/search`.

## 3. Primeiro uso (onboarding)

Na primeira execução aparecem 3 páginas (com botão "Pular" sempre disponível):
1. "Seu tempo, offline primeiro" - Calendário, tarefas, hábitos, contagens, foco, notas e listas funcionam sem conta.
2. "Alarmes que tocam" - ao criar o primeiro lembrete o app pede permissão de notificação e alarme exato; teste de alarme disponível em Ajustes.
3. "Sincronizar é opcional" - conectar Google para sincronizar calendário e tarefas, ou criar conta de e-mail para sincronizar hábitos e foco. Dados do Google nunca tocam o servidor. Pule para ficar totalmente local.

Permissões são pedidas no momento de uso, não todas de uma vez.

## 4. Calendário

Visualizações (menu de visualização no AppBar):
- Mês: grade com pontos nos dias com eventos.
- 3/4/7 dias: linha do tempo com hora atual e snap de 15 minutos.
- Dia: linha do tempo de um dia.
- Agenda: lista cronológica.
- Ano: mapa de calor.

Navegação: setas anterior/próximo, ícone "Hoje", título com mês/ano.

Criar/editar evento (FAB ou toque em horário vazio):
- Título, calendário, dia inteiro (switch).
- Datas e horas de início e fim (date/time pickers).
- Repetição: não repete, diário, semanal, mensal, anual, último dia do mês, ou RRULE customizado com validação e exemplos.
- Local, notas, participantes (separados por vírgula), link do Meet (criar Meet), cor (colorId).
- Fuso horário opcional (tzId).

Eventos recorrentes: ao editar, escolha o escopo - este evento, este e os seguintes, ou todos. Para alterações de horário em "todos", pergunta se mantém ou reseta alterações por ocorrência.

Arrastar para mover com snap de 15 minutos; em recorrentes pergunta o escopo.

Calendários (ícone de ajustes do calendário):
- Listar, ativar/desativar, adicionar calendário local.
- Configurações: início da semana (segunda/domingo/sábado), duração padrão de evento.

Notas vinculadas: adicionar a partir dos detalhes do evento; lista nos detalhes; notas longas (>8000 caracteres) viram nota de overflow.

## 5. Tarefas

Tela principal:
- Filtro por lista (chips horizontais), incluindo "All" e "+ List".
- Seção "Overdue (N)" com botão "Reschedule to today".
- Swipe para concluir ou excluir (com desfazer, 6 s).
- Ações no AppBar: Concluídas (done_all) e Lixeira.

Criar/editar (editor ou adição rápida):
- Título, lista, prioridade (0 a 4), data de vencimento, fixar, notas, tags, subtarefas (parentId).
- Adição rápida (FAB): campo único com atalho:
  - `#tag` para etiquetas.
  - `~lista` para lista (cria se não existir).
  - `-p1` a `-p4` para prioridade (-p1 = mais urgente).
  - Resto passa por parser de data/hora natural (EN e PT), incluindo recorrência.
  - Exemplo: `Buy milk #groceries ~home -p1 tomorrow 9h`.
  - Chips de pré-visualização ao vivo; "Salvar" e "Salvar e adicionar outro".

Matriz de Eisenhower (`Matrix`): quadrantes "Do first", "Schedule", "Delegate", "Eliminate" e "Unclassified", a partir de prioridade e data de vencimento, com janela de urgência configurável. Toque para editar.

Lixeira: restaurar ou excluir definitivamente; concluídas em tela separada com reabrir.

## 6. Hábitos

- Frequências: diário, dias da semana (máscara), semanal (meta de dias), a cada N dias.
- Seções (criar pela edição), arquivar/restaurar (ícone no AppBar).
- Navegador de 7 dias (faixa de dias) para marcar conclusão.
- Registro em um toque; opção de pular (skip) neutro para streaks.
- Meta quantitativa: quantidade + unidade.
- Data de início, lembrete (hora).
- Streak atual e melhor (saltos neutros não estendem a sequência).

## 7. Contagens regressivas

- Título, data alvo, repetição anual, mostrar idade, notas.
- Grupos "Próximas" e "Passadas" ordenados por dias restantes, mais não datadas.
- Editar/excluir com desfazer.

## 8. Foco

- Presets de foco: 15, 25, 50 minutos; pausas: 5, 10, 15.
- Timer baseado em timestamp (startedAt/targetEndUtc): sobrevive a fechamento do app; tick por segundo apenas com a tela visível.
- Alarme nativo de fim de sessão (AlarmScheduler).
- Histórico e estatísticas: minutos de hoje e da semana.
- Sessões podem ser associadas a hábitos/tags (conforme domínio).

## 9. Notas

- Pastas aninhadas com breadcrumbs; mover entre pastas (anti-ciclo); excluir pasta reparenta filhos.
- Notas: criar, editar, fixar, duplicar, excluir (com desfazer), lixeira.
- Editor Markdown: barra de ferramentas, alternância editar/pré-visualização, checklists tocáveis, contagem de palavras/caracteres, autosave a cada 800 ms.
- Pré-visualização leve (GitHub Flavored), lista lazy, cache por versão.
- Busca FTS5 com snippets destacados.
- Anexos em armazenamento content-addressed com limpeza de órfãos.
- Notas vinculadas a eventos (adicionar nos detalhes do evento).

## 10. Alarmes

- Agendamento de alarmes vinculados a lembretes/tarefas/foco, com janela rolante (48 h + 60 futuros).
- Intensidades: leve (exact while idle), médio/forte/constante (setAlarmClock).
- Tela de toque (`/ring`): sem voltar para dispensar, soneca de 10 minutos e "Concluído"; auto-soneca em 30 s.
- Repetição constante: a cada 1 minuto, máximo 30.
- Recuperação após reboot, mudança de hora, fuso e atualização de app (receivers + leitura direta do índice de alarmes).
- Permissões: alarme exato (conceder nas configurações do sistema), otimização de bateria (deep links).
- Teste de alarme (toca em 10 s).
- Alarmes perdidos listados em Ajustes.
- Orientação para fabricantes (Xiaomi, Samsung, Huawei, Oppo) que bloqueiam alarmes.
- Plataformas: Android completo; iOS/desktop exibem notificações enquanto o app está aberto; Web exibe banner de indisponibilidade.

## 11. Busca global

- Um campo de busca em tarefas, eventos, notas, hábitos, contagens e tags.
- Filtros por tipo (chips): Tudo, Tarefas, Eventos, Notas, Hábitos, Contagens, Tags.
- Resultados agrupados com contagem; linhas são apenas exibição (navegação profunda em versão futura).

## 12. Sincronização

Google (Calendário e Tarefas):
- Login com Google (consent-first), funciona sem conta; escopos incrementais (Calendar e depois Tasks).
- Sincronização de mão única/dupla com outbox, backoff com jitter, tratamento de 410/401/403/429 com Retry-After.
- Mapeamento preserva campos locais (alarmPreset, colorId, dueTime, prioridade, rrule).
- Chip de status: Sincronizado / Sincronizando / Offline / Erro.
- Gatilhos: tocar no título de Calendário, Tarefas ou Matriz sincroniza agora e reinicia a contagem; intervalo automático configurável (Desligado, 15 min, 30 min, 1 h, 2 h).
- Lista de alterações que falharam com "Repetir"/"Descartar".
- Dados do Google vão direto do app para o Google; nunca tocam o servidor.

Conta de e-mail (backend, opcional):
- Criar conta ou entrar (e-mail + senha de 8+ caracteres).
- Sincroniza apenas hábitos e sessões de foco entre dispositivos.
- Calendário, tarefas e notas permanecem no dispositivo.
- "Sincronizar agora", sair, "Excluir dados remotos" (remove hábitos/foco do servidor; dados locais permanecem).

## 13. Ajustes

Aparência:
- Idioma: sistema, inglês, português.
- Cor primária: 10 presets + hex customizado.
- Cor de fundo: 6 presets + hex customizado.
- Brilho: claro, escuro, AMOLED.
- Reduzir animações, haptics (vibração).

Energia e acessibilidade:
- Modo economia de energia: auto (halva frequência abaixo de 15% de bateria), sempre ligado, sempre desligado.

Navegação:
- Reordenar seções.

Conta e sincronização:
- Atalho para a tela de Conta (Google + backend).

Google sync:
- Intervalo de auto-sync (0/15/30/60/120 min).

Backup:
- Exportar: gera `ephemeron-backup-<timestamp>.json` com 21 tabelas, validado e transacional. Anexos (bytes) não incluídos.
- Restaurar: selecionar arquivo da lista e confirmar.
- Indisponível na Web ("File backups are not available on web yet.").

## 14. Plataformas e limitações conhecidas

- Web: alarmes indisponíveis; backups de arquivo indisponíveis; Drift via WASM/IndexedDB (dados persistem).
- Desktop (Linux/macOS/Windows): notificações apenas enquanto o app está aberto; configurar caminhos de som por SO.
- Android: funcionalidade completa, incluindo alarmes e recuperação após reboot.
- Sem SDK/dispositivo: matriz de alarmes em dispositivos físicos, benchmark de bateria 24 h, auditoria de tamanho não verificados (ver `docs/TODO.md`).

## 15. Privacidade e segurança (resumo)

- Eventos, tarefas, notas, contagens e etiquetas nunca saem do dispositivo, exceto na sincronização com o Google (direto do app para os servidores do Google).
- Servidor armazena apenas e-mail, hash da senha, hábitos, registros de hábitos e sessões de foco (com conta de e-mail).
- Tokens em armazenamento seguro (keystore); nunca em SharedPreferences, logs ou backups.
- Sem analytics, anúncios ou coleta de localização.
- Sem rastreamento. Exportar dados via Ajustes > Backup; excluir dados remotos via Conta > Excluir dados remotos.
- Detalhes: `docs/PRIVACY.md`, `docs/SECURITY_REVIEW.md`.

## 16. Mapa da documentação

- `docs/ARCHITECTURE.md`: arquitetura e especificação.
- `docs/PRIVACY.md`: política de privacidade (rascunho).
- `docs/SECURITY_REVIEW.md`: revisão de segurança.
- `docs/PROGRESS.md`: status das fases.
- `docs/TODO.md`: pendências e limites de ambiente.
- `docs/decisions.md`: decisões de implementação.
- `app/README.md`: setup e versões.