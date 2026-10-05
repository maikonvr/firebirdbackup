# Spec — Utilitário de backup Firebird 2.5 (Delphi VCL)

Data: 2026-10-05. Status: aprovada em chat, aguardando execução.

## Problema

Os servidores (Windows Server 2019, Firebird 2.5) precisam de cópias diárias do banco sem depender de
scripts manuais nem de ferramenta pesada. Copiar o `.FDB` a quente corrompe a cópia; `gbak` com garbage
collection pesa no servidor; não há rotina de descarte de cópias antigas.

## Objetivo

Uma exe Delphi 10.3 (VCL, 32 bits, sem runtime extra) que, uma vez por dia, gera para cada banco
configurado uma cópia lógica (`.fbk`, via `gbak`) e uma cópia física (`.fdb`, via `nbackup`) em uma
pasta local, apaga as cópias com mais de N dias (padrão 7) e mostra andamento e parâmetros em uma
tela simples que qualquer usuário consiga configurar.

## Comportamento esperado

### Modos de execução (mesma exe)

| Chamada | Comportamento |
|---|---|
| `FirebirdBackup.exe` | Abre o form principal, ícone na bandeja, `TTimer` de 60 s. Quando o horário configurado já passou e a última execução registrada em `ultimo-status.ini` não é de hoje, executa o backup em thread (cobre app aberto atrasado e não repete se a tarefa agendada já rodou hoje). Fechar a janela minimiza para a bandeja; sair só pelo menu da bandeja. |
| `FirebirdBackup.exe --run` | Não cria form. Executa o backup uma vez, grava log e status, sai com código 0 (sucesso) ou 1 (qualquer falha). Usado pela tarefa do Agendador. |

Instância única no modo normal (mutex nomeado): abrir a exe de novo traz a janela existente para frente.

### Sequência de um backup (por banco, em ordem)

1. Recuperação: se existir `<destino>\<nome>.lock-pendente`, roda `nbackup -N` no banco e apaga o
   marcador antes de qualquer coisa.
2. Verifica espaço livre no destino: exige pelo menos `2 × tamanho do FDB` quando as duas cópias estão
   ativas (`1 ×` se só uma). Se faltar, registra erro e pula o banco.
3. Cópia `.fbk` (se `CopiaFbk=1`):
   `gbak -b -g -v -se localhost:service_mgr <arquivo> <destino>\<nome>_<AAAA-MM-DD_HHMM>.fbk`
   Saída do `-v` vai linha a linha para o log e para a tela.
4. Cópia `.fdb` (se `CopiaFdb=1`):
   `nbackup -L <arquivo>` → grava `.lock-pendente` → `CopyFile` para
   `<destino>\<nome>_<AAAA-MM-DD_HHMM>.fdb` → `nbackup -N <arquivo>` → apaga `.lock-pendente` →
   `nbackup -F <cópia>`. Se o `-L` falhar, não copia. Se a cópia falhar, ainda executa o `-N`.
   Se o `-N` falhar, o `.lock-pendente` permanece e o `-F` não roda.
5. Retenção: apaga em `<destino>` os arquivos cujo nome casa exatamente com
   `<nome>_AAAA-MM-DD_HHMM.fbk` ou `.fdb` de um banco configurado e cuja data de modificação é
   anterior a `agora − RetencaoDias`. Nenhum outro arquivo é tocado.
6. Status: grava `ultimo-status.ini` no destino (`[<nome>]`: `Inicio`, `Fim`, `DuracaoSeg`, `Resultado`
   = `OK`/`ERRO`, `Mensagem`, `TamanhoFbk`, `TamanhoFdb`).

Um banco com erro não impede os seguintes. O resultado geral é `ERRO` se qualquer banco falhou.

### Execução dos utilitários do Firebird

- Usa `gbak.exe` e `nbackup.exe` da pasta `FirebirdDir` configurada (a instalação 2.5 do servidor).
  Se algum não existir, erro de configuração antes de iniciar.
- `CreateProcess` com `stdout`/`stderr` redirecionados por pipe, janela oculta, prioridade
  `BELOW_NORMAL`. Usuário e senha vão nas variáveis de ambiente `ISC_USER` e `ISC_PASSWORD` do
  processo filho, nunca na linha de comando.
- Código de saída diferente de 0 = falha daquela etapa; a última linha da saída vira `Mensagem`.

### Configuração — `backup.ini` ao lado da exe

```ini
[Geral]
FirebirdDir=C:\Program Files\Firebird\Firebird_2_5
Usuario=SYSDBA
Senha=masterkey
Destino=D:\Backup
RetencaoDias=7
Horario=02:00
CopiaFbk=1
CopiaFdb=1

[Banco1]
Nome=AG2006
Arquivo=D:\Dados\AG2006.FDB

[Banco2]
Nome=OUTRO
Arquivo=D:\Dados\OUTRO.FDB
```

Seções `[BancoN]` numeradas a partir de 1, lidas até a primeira ausente. `Nome` é usado no nome dos
arquivos gerados; aceita só letras, dígitos, `-` e `_`. Senha em texto puro, protegida por permissão
de pasta (decisão: simplicidade; cifrar é evolução futura).

Validações ao carregar/salvar: `FirebirdDir` contém `gbak.exe` e `nbackup.exe`; `Destino` existe ou é
criável; `RetencaoDias` ≥ 1; `Horario` no formato `HH:MM`; cada `Arquivo` existe; ao menos uma das
cópias ativa; ao menos um banco.

### Log

`<destino>\backup_AAAA-MM-DD.log`, texto, uma linha por evento com `hh:nn:ss`. Inclui comandos
executados (sem senha), saída do `gbak -v`, erros e arquivos apagados pela retenção. Logs seguem a
mesma retenção dos backups.

### Tela (form único)

- Grupo **Firebird**: pasta (com botão procurar), usuário, senha (mascarada).
- Grupo **Bancos**: lista (nome, arquivo) com Adicionar/Remover/Editar; arquivo com botão procurar.
- Grupo **Destino e rotina**: pasta destino, retenção em dias, horário, checkboxes fbk e fdb.
- Botões: **Salvar**, **Agendar** (cria/atualiza via `schtasks /Create /F` a tarefa diária
  `FirebirdBackup` com `/RU SYSTEM`, executando `<exe> --run` no horário configurado; mostra o
  resultado), **Executar agora**.
- Andamento: `TMemo` somente leitura recebendo as linhas do log em tempo real, `TProgressBar` em modo
  marquee enquanto roda; botões desabilitados durante a execução.
- Painel **Último backup**: lê `ultimo-status.ini` e mostra por banco: início, duração, resultado,
  tamanhos. Atualiza ao abrir e ao terminar uma execução.
- `TTrayIcon` com menu: Abrir, Executar agora, Sair. Balão de aviso quando um backup termina com erro.

### Erros e casos de borda

- Horário virando o dia durante a execução: o timer só dispara uma vez por data civil (compara a
  data de `UltimaExecucao` do status com a data atual).
- Backup já em andamento (timer ou botão): o novo pedido é ignorado e registrado no log.
- Destino em outra unidade indisponível: falha no passo 2, registrada; nada é apagado.
- Processo encerrado no meio do `nbackup -L`: o `.lock-pendente` garante o `-N` na próxima execução.

## Fora de escopo

Restore de teste automático, envio para rede/nuvem, compactação, e-mail/alerta remoto, serviço
Windows, cifra da senha, suporte a Firebird embedded ou remoto (o app roda na máquina do servidor).

## Decisões

- Delphi VCL em vez de .NET: ecossistema do ERP, exe única, sem runtime.
- INI em vez de JSON: nativo no Delphi e editável por leigo sem quebrar sintaxe.
- `gbak -se service_mgr` e `-g`: roda dentro do servidor, sem rede, sem garbage collection.
- `nbackup -L/-N/-F` em vez de copiar o FDB direto: única forma segura de cópia física a quente.
- Timer no form **e** modo `--run`: atende "aplicativo com timer" e cobre servidor sem sessão logada.
- Units com prefixo `p` (`pConfig`, `pBackup`, `pLog`, `pPrincipal`), padrão do usuário.

## Estrutura

```
FirebirdBackup/
  FirebirdBackup.dpr / .dproj
  src/pConfig.pas      TConfig: carregar/salvar/validar backup.ini
  src/pLog.pas         TLog: arquivo diário + evento OnLinha para a tela
  src/pProcesso.pas    ExecutarProcesso(exe, args, env, OnLinha): CreateProcess + pipe
  src/pBackup.pas      TBackup: sequência por banco, retenção, status; roda em TThread
  src/pPrincipal.pas/.dfm  form, tray, timer, agendar
  docs/plans/          esta spec e o plan
  backup.ini.exemplo
```

## Critérios de aceitação

1. `--run` com um banco de teste gera `.fbk` e `.fdb` no destino, o `.fdb` abre com `isql`, e o
   código de saída é 0.
2. Arquivos no padrão de nome mais antigos que a retenção são apagados; um arquivo estranho na mesma
   pasta permanece.
3. Com `.lock-pendente` presente e banco travado, a execução destrava o banco antes de prosseguir.
4. `gbak` ausente na pasta configurada produz erro de configuração claro, sem iniciar o backup.
5. A tela carrega e salva o INI sem perder campos, roda "Executar agora" mostrando as linhas do
   `gbak -v`, e o painel de último backup reflete o resultado.
6. Modo normal: o timer dispara no horário configurado uma única vez por dia.
