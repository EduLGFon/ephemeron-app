# Privacy Policy (DRAFT - needs owner and lawyer sign-off before release)

> This is an engineering draft describing how the app handles data today.
> It is not legal advice. Do not publish without review.

## English

**What stays only on your device.** Calendar events, tasks, notes,
countdowns and tags never leave your device except when you connect
Google sync, in which case they go directly from the app to Google's
servers. Our server never receives them.

**What our server stores (only with an email account).** If you create an
email account for habit/focus sync, the server stores your email and
password hash plus your habits, habit logs and focus sessions. Nothing
else. Data is used only to sync your devices.

**Tokens.** Sign-in tokens are kept in your device's secure storage
(keystore) and never in backups of app data made by the OS without
exclusion rules (see SECURITY_REVIEW.md).

**No tracking.** The app contains no analytics, advertising or
crash-reporting SDKs. No location, Bluetooth or sensor data is collected.

**Your rights (LGPD).** You can export your data (Settings > Backup) and
request deletion: Settings > Account > Delete remote data removes your
habits and focus data from the server. Contact details of the data
controller (DPO) must be added here before release.

**Retention.** Local data stays until you delete it. Server habit/focus
data is deleted on account deletion.

## Português (resumo)

**O que fica só no seu dispositivo.** Eventos, tarefas, notas, contagens
e etiquetas nunca saem do dispositivo, exceto na sincronização com o
Google, que vai direto do app para os servidores do Google. Nosso
servidor nunca os recebe.

**O que nosso servidor guarda (só com conta de e-mail).** E-mail, hash da
senha, hábitos, registros de hábitos e sessões de foco. Nada mais.

**Sem rastreamento.** Sem analytics, anúncios ou coleta de localização.

**Seus direitos (LGPD).** Exporte seus dados (Ajustes > Backup) e peça
exclusão (Conta > Excluir dados remotos). Adicionar aqui o contato do
controlador/DPO antes do lançamento.
