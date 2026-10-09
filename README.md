# FirebirdBackup

Utilitário leve para backup diário de bancos Firebird 2.5 em Windows. Uma exe só, sem runtime.

Para cada banco configurado gera, na pasta de destino:

- `NOME_AAAA-MM-DD_HHMM.fbk` — cópia lógica via `gbak -b -g -v -se localhost:service_mgr`
- `NOME_AAAA-MM-DD_HHMM.fdb` — cópia física a quente via `nbackup -L` / cópia / `-N` / `-F`
- `backup_AAAA-MM-DD.log` e `ultimo-status.ini`

Arquivos com mais de N dias (padrão 7, pela data no nome) são apagados; nada fora desse padrão de nome é tocado.

O `.fbk` é escrito pelo **processo do servidor Firebird** (via Services API), não pela exe: a pasta de destino precisa ser gravável também pela conta do serviço Firebird (por padrão, `SYSTEM`). A cópia `.fdb` é feita pela exe (ou pela conta da tarefa agendada).

## Uso no servidor

1. Copie `bin\FirebirdBackup.exe` para uma pasta no servidor onde o Firebird roda (ex.: `C:\FirebirdBackup`).
2. Abra a exe, preencha pasta do Firebird 2.5, usuário/senha, destino, retenção, horário e os bancos. **Salvar** grava `backup.ini` ao lado da exe.
3. Escolha como rodar:
   - **Agendar no Windows** (recomendado): cria a tarefa diária `FirebirdBackup`, que roda `FirebirdBackup.exe --run` mesmo sem usuário logado. Precisa de sessão administrativa.
   - Deixar a exe aberta na bandeja: o timer dispara no horário (ou na primeira oportunidade do dia, se o app estava fechado).
   - Com os dois ativos no mesmo horário, a tarefa (SYSTEM) roda e o timer da tela se limita a registrar "backup já em andamento em outro processo" até ela terminar. Nunca rodam em paralelo: o `.fbk` dos dois teria o mesmo nome e o segundo gbak falharia com "cannot open backup file".
4. **Executar agora** roda na hora e mostra o andamento na tela.

`FirebirdBackup.exe --run` sai com 0 (OK), 1 (algum banco falhou) ou 2 (configuração inválida; erro gravado em `backup_*.log` ao lado da exe).

A senha fica em texto no `backup.ini`: proteja a pasta por permissão NTFS.

## Compilar

Delphi 10.3 Rio. `build.cmd` gera `bin\FirebirdBackup.exe`; `testar.cmd` compila e roda os testes DUnitX. O `.dproj` abre no IDE.

Spec e plan em `docs/plans/`.
