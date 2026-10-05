# Plan — Utilitário de backup Firebird 2.5 (Delphi VCL)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exe Delphi 10.3 que faz backup diário (`.fbk` via gbak, `.fdb` via nbackup) de bancos Firebird 2.5, com retenção configurável, INI, tela única com timer e modo `--run`.

**Architecture:** Lógica em units sem VCL (`pConfig`, `pLog`, `pProcesso`, `pBackup`, `pAgenda`) testadas por DUnitX em console; o form `pPrincipal` só orquestra (thread, tray, timer). `TBackup` recebe um executor injetável para que os testes não dependam do Firebird; um teste de integração manual usa o Firebird 3.0 local.

**Tech Stack:** Delphi 10.3 Rio (dcc32 32 bits), VCL, DUnitX (fonte em `$(BDS)\source\DUnitX`), Firebird `gbak`/`nbackup`, `schtasks`.

**Spec:** `docs/plans/2026-10-05-firebird-backup-spec.md`

## Status (2026-10-05): concluído

**Validações rodadas**
- `testar.cmd`: 41 testes DUnitX passando (pConfig 10, pLog 3, pProcesso 6, pBackup 15, pAgenda 6, sanidade 1).
- `build.cmd` e `msbuild FirebirdBackup.dproj`: build limpo, sem warnings.
- Integração com Firebird 3.0 local (mesmos comandos do 2.5): `--run` gerou `.fbk` e `.fdb`, exit 0; a cópia `.fdb` abriu no `isql`; o `.fbk` restaurou com `gbak -c`; com banco travado e marcador `.lock-pendente`, o `-N` rodou antes do `-L` e o banco ficou destravado; `--run` sem `backup.ini` retorna 2 com o erro no log.
- Tela: abre com padrões; Salvar regrava o INI idêntico; Executar agora rola o `gbak -v` e atualiza o painel; fechar vai para a bandeja; segunda instância não abre; `schtasks` com os argumentos gerados cria a tarefa como SISTEMA (criada e apagada no teste); timer disparou uma vez no horário.

**Desvios do plan**
- Timer: dispara quando o horário já passou e a última execução não é de hoje (spec atualizada).
- `nbackup -F` só roda se o `-N` normal retornou 0; se o `-N` falha, o marcador fica para nova tentativa.
- `TFile.GetSize` não existe no 10.3: helper `TamanhoArquivo` em `pBackup`.
- Ícone gerado por script (32×32) porque `brcc32` rejeita o `.ico` padrão do Delphi (camadas PNG 256px).
- Ajustes só em código de teste: `AddStrings` com open array, `echo erro>&2`, `ExecutorFalso()`, data real no teste de retenção.

**Revisão final independente (2026-10-05) e correções aplicadas** (suíte passou a 48 testes)
- Crítico: `--run` sem guarda de exceção podia deixar a tarefa agendada pendurada em um MessageBox na sessão 0. Agora `ModoRun` captura tudo e sai com 1; cada banco converte exceção em falha própria (`TestExcecaoNoExecutorViraFalhaENaoImpedeSeguinte`); retenção e status protegidos (`TestExecutarComDestinoInvalidoNaoLevanta`); a thread da tela loga `ERRO fatal`. Verificado com destino inválido (`exit 2`) e `ultimo-status.ini` não gravável (`exit 1`, sem travar).
- Marcador `.lock-pendente` só é apagado quando o `-N` de recuperação retorna 0 (`TestLockPendenteRecuperacaoFalhaMantemMarcador`).
- Mutex global `Global\FirebirdBackup_Execucao` em `TBackup.Executar`: tarefa agendada e tela não rodam ao mesmo tempo; o segundo registra "já em andamento" (`TestExecutarConcorrenteSaiComAviso`). A tela também checa antes de iniciar.
- Saída de `gbak`/`nbackup` é ANSI, não OEM: conversão OEM virou opcional (`AConverterOem`), usada só pelo `schtasks` (`TestSaidaAnsiSemConversaoPorPadrao`, `TestSaidaOemConvertida`).
- Timer usa só a configuração salva no `backup.ini` e não grava nada; `Executar agora` continua salvando a tela. Verificado: destino digitado e não salvo foi ignorado e não persistido.
- Tempo limite por processo (padrão 6 h em `TBackup.TimeoutMs`) com polling do pipe e `TerminateProcess` (`TestTimeoutEncerraProcesso`); `schtasks` com 60 s.
- `UltimaExecucao` passa a ser a hora de início do run, senão um backup que cruza a meia-noite faz o timer pular o dia seguinte (`TestStatusUsaHoraDeInicio`).

**Pendências menores registradas (não corrigidas)**: marcador escrito só após o `-L` (janela mínima); retenção por `LastWriteTime` em vez da data do nome; segunda instância restaurada por `ShowWindow` externo pode deixar o `Hide` sem efeito; `LimitarMemo` só ao terminar; `Validar` não exige senha; README não cita que o destino precisa ser gravável pela conta do serviço Firebird e omite o `-v`; integração validada só no Firebird 3.0 (fazer um `--run` de teste no 2.5 real antes do primeiro uso). Restore fica fora (decisão do usuário); senha cifrada e teste de restore automático são evoluções futuras.

## Global Constraints

- Units com prefixo `p` (`pConfig.pas`, `pBackup.pas`, …); nunca `u`.
- Compilação 32 bits com `dcc32`; sem pacotes de terceiros; só RTL/VCL/DUnitX.
- Senha nunca em linha de comando nem em log: só `ISC_USER`/`ISC_PASSWORD` no ambiente do filho.
- Retenção apaga apenas arquivos que casam `<Nome>_AAAA-MM-DD_HHMM.fbk|.fdb` e `backup_AAAA-MM-DD.log`.
- Processos filhos: janela oculta, prioridade `BELOW_NORMAL`.
- Sem repositório git na pasta: não comitar por conta própria (regra global do usuário). Se o usuário pedir `git init`, cada task vira um commit.
- Encoding dos `.pas`: UTF-8 com BOM, CRLF (Delphi). Arquivos gravados pela ferramenta Write já saem CRLF.

## Review Focus

1. Caminhos com espaço (`C:\Program Files\...`): todo argumento de `gbak`/`nbackup`/`schtasks` vai entre aspas. Teste em Task 6 (`TestComandoGbakComEspacos`) e Task 7 (`TestComandoSchtasks`).
2. `nbackup -N` em banco que não está travado (marcador `.lock-pendente` órfão): não pode abortar o backup; vira aviso no log. Teste em Task 6 (`TestLockPendenteOrfaoNaoAborta`).
3. Saída do `gbak -v` em codepage OEM (acentos em mensagens de erro): converter OEM→ANSI antes de exibir. Teste em Task 4 (`TestSaidaOemConvertida`).
4. INI com chave ausente ou valor inválido (`RetencaoDias=abc`, `Horario=2:0`): carregar com padrão e `Validar` apontar o campo. Teste em Task 2 (`TestValidarHorarioInvalido`, `TestCarregarChaveAusenteUsaPadrao`).
5. App aberto depois do horário (foi ligado às 10:00, backup era 02:00 e não rodou hoje): deve rodar na primeira oportunidade do dia, e **não** rodar de novo se a tarefa agendada já rodou hoje. Teste em Task 7 (`TestDisparaAtrasadoUmaVez`, `TestNaoDisparaSeJaRodouHoje`).

---

### Task 1: Esqueleto do projeto, scripts de build e primeiro teste DUnitX

**Files:**
- Create: `FirebirdBackup.dpr`, `build.cmd`, `testar.cmd`, `tests/Testes.dpr`, `backup.ini.exemplo`, `.gitignore`

**Interfaces:**
- Produces: `build.cmd` gera `bin\FirebirdBackup.exe`; `testar.cmd` compila e roda `bin\Testes.exe`, retornando código ≠ 0 se algum teste falhar. Todas as tasks seguintes usam `testar.cmd`.

- [ ] **Step 1: Criar `build.cmd`** (CRLF)

```bat
@echo off
setlocal
cd /d %~dp0
call "C:\Program Files (x86)\Embarcadero\Studio\20.0\bin\rsvars.bat"
if not exist bin mkdir bin
if not exist dcu mkdir dcu
dcc32 -Q -B -$O+ -$D- -Ebin -N0dcu -Usrc -Rsrc -U"%BDS%\lib\win32\release" -NSSystem;Winapi;Vcl;Vcl.Imaging FirebirdBackup.dpr
exit /b %ERRORLEVEL%
```

- [ ] **Step 2: Criar `testar.cmd`** (CRLF)

```bat
@echo off
setlocal
cd /d %~dp0
call "C:\Program Files (x86)\Embarcadero\Studio\20.0\bin\rsvars.bat"
if not exist bin mkdir bin
if not exist dcu mkdir dcu
dcc32 -Q -B -Ebin -N0dcu -Usrc;tests -U"%BDS%\source\DUnitX;%BDS%\lib\win32\release" -NSSystem;Winapi;Vcl tests\Testes.dpr
if errorlevel 1 exit /b 1
bin\Testes.exe
exit /b %ERRORLEVEL%
```

- [ ] **Step 3: Criar `tests/Testes.dpr`** com um teste trivial

```pascal
program Testes;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  pTesteSanidade in 'pTesteSanidade.pas';

var
  Runner: ITestRunner;
  Logger: ITestLogger;
  Resultados: IRunResults;
begin
  try
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    Resultados := Runner.Execute;
    if not Resultados.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
```

- [ ] **Step 4: Criar `tests/pTesteSanidade.pas`**

```pascal
unit pTesteSanidade;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTesteSanidade = class
  public
    [Test]
    procedure TestAmbienteCompila;
  end;

implementation

procedure TTesteSanidade.TestAmbienteCompila;
begin
  Assert.AreEqual(2, 1 + 1);
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteSanidade);

end.
```

- [ ] **Step 5: Criar `FirebirdBackup.dpr`** mínimo (sem form ainda)

```pascal
program FirebirdBackup;

uses
  Vcl.Forms,
  System.SysUtils;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Run;
end.
```

Como não existe `FirebirdBackup.res`, remover a linha `{$R *.res}` até a Task 8 (onde o ícone entra) **ou** gerar um `.res` vazio: `brcc32` não é necessário; basta omitir a diretiva nesta task.

- [ ] **Step 6: Criar `backup.ini.exemplo`** com o conteúdo exato da seção "Configuração" da spec, e `.gitignore`:

```
bin/
dcu/
*.local
*.identcache
*.stat
__history/
backup.ini
```

- [ ] **Step 7: Rodar `testar.cmd` e `build.cmd`**

Run: `cmd /c C:\Sistemas\Bulls\FirebirdBackup\testar.cmd`
Expected: `Tests Passed : 1`, exit 0.
Run: `cmd /c C:\Sistemas\Bulls\FirebirdBackup\build.cmd`
Expected: `bin\FirebirdBackup.exe` existe, exit 0.

---

### Task 2: `pConfig` — carregar, salvar e validar `backup.ini`

**Files:**
- Create: `src/pConfig.pas`, `tests/pTesteConfig.pas`
- Modify: `tests/Testes.dpr` (adicionar a unit na cláusula `uses`)

**Interfaces:**
- Produces:
  ```pascal
  TBancoConfig = record Nome, Arquivo: string; end;
  TConfig = class
    FirebirdDir, Usuario, Senha, Destino, Horario: string;
    RetencaoDias: Integer; CopiaFbk, CopiaFdb: Boolean;
    Bancos: TList<TBancoConfig>;
    procedure Carregar(const AArquivo: string);
    procedure Salvar(const AArquivo: string);
    function Validar(out AErro: string): Boolean;
    function Gbak: string;      // FirebirdDir\gbak.exe
    function Nbackup: string;   // FirebirdDir\nbackup.exe
    class function ArquivoPadrao: string;   // pasta da exe + backup.ini
    class function NomeValido(const ANome: string): Boolean;
    class function HorarioValido(const AHorario: string): Boolean;
  end;
  ```

- [ ] **Step 1: Escrever os testes `tests/pTesteConfig.pas`**

```pascal
unit pTesteConfig;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Classes, pConfig;

type
  [TestFixture]
  TTesteConfig = class
  private
    FPasta: string;
    FFb: string;
    function Gravar(const ALinhas: array of string): string;
    procedure CriarFirebirdFalso;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestCarregarGeralEBancos;
    [Test] procedure TestCarregarChaveAusenteUsaPadrao;
    [Test] procedure TestSalvarECarregarIdaEVolta;
    [Test] procedure TestValidarOk;
    [Test] procedure TestValidarHorarioInvalido;
    [Test] procedure TestValidarSemGbak;
    [Test] procedure TestValidarNomeInvalido;
    [Test] procedure TestValidarSemBanco;
    [Test] procedure TestValidarNenhumaCopia;
    [Test] procedure TestValidarRetencaoMenorQueUm;
  end;

implementation

procedure TTesteConfig.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_cfg_' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(FPasta);
  FFb := TPath.Combine(FPasta, 'fb');
end;

procedure TTesteConfig.TearDown;
begin
  TDirectory.Delete(FPasta, True);
end;

function TTesteConfig.Gravar(const ALinhas: array of string): string;
var
  L: TStringList;
begin
  Result := TPath.Combine(FPasta, 'backup.ini');
  L := TStringList.Create;
  try
    L.AddStrings(ALinhas);
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

procedure TTesteConfig.CriarFirebirdFalso;
begin
  TDirectory.CreateDirectory(FFb);
  TFile.WriteAllText(TPath.Combine(FFb, 'gbak.exe'), '');
  TFile.WriteAllText(TPath.Combine(FFb, 'nbackup.exe'), '');
  TFile.WriteAllText(TPath.Combine(FPasta, 'A.FDB'), '');
end;

procedure TTesteConfig.TestCarregarGeralEBancos;
var
  C: TConfig;
begin
  C := TConfig.Create;
  try
    C.Carregar(Gravar(['[Geral]', 'FirebirdDir=C:\FB', 'Usuario=SYSDBA', 'Senha=x',
      'Destino=D:\Bk', 'RetencaoDias=10', 'Horario=23:30', 'CopiaFbk=1', 'CopiaFdb=0',
      '[Banco1]', 'Nome=A', 'Arquivo=D:\A.FDB', '[Banco2]', 'Nome=B', 'Arquivo=D:\B.FDB',
      '[Banco4]', 'Nome=NAO_LIDO', 'Arquivo=D:\X.FDB']));
    Assert.AreEqual('C:\FB', C.FirebirdDir);
    Assert.AreEqual('SYSDBA', C.Usuario);
    Assert.AreEqual('x', C.Senha);
    Assert.AreEqual('D:\Bk', C.Destino);
    Assert.AreEqual(10, C.RetencaoDias);
    Assert.AreEqual('23:30', C.Horario);
    Assert.IsTrue(C.CopiaFbk);
    Assert.IsFalse(C.CopiaFdb);
    Assert.AreEqual(2, C.Bancos.Count);
    Assert.AreEqual('B', C.Bancos[1].Nome);
    Assert.AreEqual('D:\B.FDB', C.Bancos[1].Arquivo);
    Assert.AreEqual('C:\FB\gbak.exe', C.Gbak);
    Assert.AreEqual('C:\FB\nbackup.exe', C.Nbackup);
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestCarregarChaveAusenteUsaPadrao;
var
  C: TConfig;
begin
  C := TConfig.Create;
  try
    C.Carregar(Gravar(['[Geral]', 'RetencaoDias=abc']));
    Assert.AreEqual(7, C.RetencaoDias);
    Assert.AreEqual('02:00', C.Horario);
    Assert.AreEqual('SYSDBA', C.Usuario);
    Assert.IsTrue(C.CopiaFbk);
    Assert.IsTrue(C.CopiaFdb);
    Assert.AreEqual(0, C.Bancos.Count);
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestSalvarECarregarIdaEVolta;
var
  C, D: TConfig;
  B: TBancoConfig;
  Arq: string;
begin
  Arq := TPath.Combine(FPasta, 'novo.ini');
  C := TConfig.Create;
  D := TConfig.Create;
  try
    C.FirebirdDir := 'C:\FB'; C.Usuario := 'U'; C.Senha := 'S'; C.Destino := 'D:\Bk';
    C.RetencaoDias := 3; C.Horario := '01:15'; C.CopiaFbk := False; C.CopiaFdb := True;
    B.Nome := 'AG'; B.Arquivo := 'D:\AG.FDB'; C.Bancos.Add(B);
    B.Nome := 'XY'; B.Arquivo := 'D:\XY.FDB'; C.Bancos.Add(B);
    C.Salvar(Arq);
    // Salvar de novo com um banco a menos não pode deixar [Banco2] órfão
    C.Bancos.Delete(1);
    C.Salvar(Arq);
    D.Carregar(Arq);
    Assert.AreEqual('C:\FB', D.FirebirdDir);
    Assert.AreEqual('S', D.Senha);
    Assert.AreEqual(3, D.RetencaoDias);
    Assert.AreEqual('01:15', D.Horario);
    Assert.IsFalse(D.CopiaFbk);
    Assert.IsTrue(D.CopiaFdb);
    Assert.AreEqual(1, D.Bancos.Count);
    Assert.AreEqual('AG', D.Bancos[0].Nome);
  finally
    C.Free; D.Free;
  end;
end;

procedure TTesteConfig.TestValidarOk;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := TPath.Combine(FPasta, 'dest');
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsTrue(C.Validar(Erro), Erro);
    Assert.IsTrue(TDirectory.Exists(C.Destino), 'Validar deve criar o destino');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarHorarioInvalido;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := FPasta; C.Horario := '2:0';
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'Horario');
    Assert.IsFalse(TConfig.HorarioValido('24:00'));
    Assert.IsFalse(TConfig.HorarioValido('12:60'));
    Assert.IsTrue(TConfig.HorarioValido('00:00'));
    Assert.IsTrue(TConfig.HorarioValido('23:59'));
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarSemGbak;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  TFile.Delete(TPath.Combine(FFb, 'gbak.exe'));
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := FPasta;
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'gbak.exe');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarNomeInvalido;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := FPasta;
    B.Nome := 'A B'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'Nome');
    Assert.IsTrue(TConfig.NomeValido('AG2006_x-1'));
    Assert.IsFalse(TConfig.NomeValido(''));
    Assert.IsFalse(TConfig.NomeValido('a.b'));
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarSemBanco;
var
  C: TConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := FPasta;
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'banco');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarNenhumaCopia;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := FPasta; C.CopiaFbk := False; C.CopiaFdb := False;
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'cópia');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarRetencaoMenorQueUm;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Destino := FPasta; C.RetencaoDias := 0;
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'RetencaoDias');
  finally
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteConfig);

end.
```

- [ ] **Step 2: Adicionar `pTesteConfig in 'pTesteConfig.pas'` e `pConfig in '..\src\pConfig.pas'` ao `uses` de `tests/Testes.dpr`; rodar `testar.cmd`**

Expected: falha de compilação (`pConfig` não encontrada).

- [ ] **Step 3: Implementar `src/pConfig.pas`**

```pascal
unit pConfig;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.Generics.Collections;

type
  TBancoConfig = record
    Nome: string;
    Arquivo: string;
  end;

  TConfig = class
  public
    FirebirdDir: string;
    Usuario: string;
    Senha: string;
    Destino: string;
    RetencaoDias: Integer;
    Horario: string;
    CopiaFbk: Boolean;
    CopiaFdb: Boolean;
    Bancos: TList<TBancoConfig>;
    constructor Create;
    destructor Destroy; override;
    procedure Carregar(const AArquivo: string);
    procedure Salvar(const AArquivo: string);
    function Validar(out AErro: string): Boolean;
    function Gbak: string;
    function Nbackup: string;
    class function ArquivoPadrao: string;
    class function NomeValido(const ANome: string): Boolean;
    class function HorarioValido(const AHorario: string): Boolean;
  end;

implementation

uses
  System.IOUtils, System.Character;

const
  SGeral = 'Geral';

constructor TConfig.Create;
begin
  inherited;
  Bancos := TList<TBancoConfig>.Create;
  Usuario := 'SYSDBA';
  RetencaoDias := 7;
  Horario := '02:00';
  CopiaFbk := True;
  CopiaFdb := True;
end;

destructor TConfig.Destroy;
begin
  Bancos.Free;
  inherited;
end;

class function TConfig.ArquivoPadrao: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'backup.ini');
end;

class function TConfig.NomeValido(const ANome: string): Boolean;
var
  C: Char;
begin
  Result := ANome <> '';
  for C in ANome do
    if not (C.IsLetterOrDigit or (C = '_') or (C = '-')) or (Ord(C) > 127) then
      Exit(False);
end;

class function TConfig.HorarioValido(const AHorario: string): Boolean;
var
  H, M: Integer;
begin
  Result := (Length(AHorario) = 5) and (AHorario[3] = ':')
    and TryStrToInt(Copy(AHorario, 1, 2), H) and TryStrToInt(Copy(AHorario, 4, 2), M)
    and (H >= 0) and (H <= 23) and (M >= 0) and (M <= 59);
end;

function TConfig.Gbak: string;
begin
  Result := TPath.Combine(FirebirdDir, 'gbak.exe');
end;

function TConfig.Nbackup: string;
begin
  Result := TPath.Combine(FirebirdDir, 'nbackup.exe');
end;

procedure TConfig.Carregar(const AArquivo: string);
var
  Ini: TIniFile;
  I: Integer;
  Secao: string;
  B: TBancoConfig;
begin
  Ini := TIniFile.Create(AArquivo);
  try
    FirebirdDir := Ini.ReadString(SGeral, 'FirebirdDir', '');
    Usuario := Ini.ReadString(SGeral, 'Usuario', 'SYSDBA');
    Senha := Ini.ReadString(SGeral, 'Senha', '');
    Destino := Ini.ReadString(SGeral, 'Destino', '');
    RetencaoDias := StrToIntDef(Ini.ReadString(SGeral, 'RetencaoDias', '7'), 7);
    Horario := Ini.ReadString(SGeral, 'Horario', '02:00');
    CopiaFbk := Ini.ReadString(SGeral, 'CopiaFbk', '1') = '1';
    CopiaFdb := Ini.ReadString(SGeral, 'CopiaFdb', '1') = '1';
    Bancos.Clear;
    I := 1;
    while True do
    begin
      Secao := 'Banco' + IntToStr(I);
      if not Ini.SectionExists(Secao) then
        Break;
      B.Nome := Ini.ReadString(Secao, 'Nome', '');
      B.Arquivo := Ini.ReadString(Secao, 'Arquivo', '');
      Bancos.Add(B);
      Inc(I);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TConfig.Salvar(const AArquivo: string);
var
  Ini: TIniFile;
  I: Integer;
  Secao: string;
begin
  Ini := TIniFile.Create(AArquivo);
  try
    Ini.WriteString(SGeral, 'FirebirdDir', FirebirdDir);
    Ini.WriteString(SGeral, 'Usuario', Usuario);
    Ini.WriteString(SGeral, 'Senha', Senha);
    Ini.WriteString(SGeral, 'Destino', Destino);
    Ini.WriteString(SGeral, 'RetencaoDias', IntToStr(RetencaoDias));
    Ini.WriteString(SGeral, 'Horario', Horario);
    Ini.WriteString(SGeral, 'CopiaFbk', IfThen(CopiaFbk, '1', '0'));
    Ini.WriteString(SGeral, 'CopiaFdb', IfThen(CopiaFdb, '1', '0'));
    // Remove seções [BancoN] antigas para não deixar órfãs
    I := 1;
    while Ini.SectionExists('Banco' + IntToStr(I)) do
    begin
      Ini.EraseSection('Banco' + IntToStr(I));
      Inc(I);
    end;
    for I := 0 to Bancos.Count - 1 do
    begin
      Secao := 'Banco' + IntToStr(I + 1);
      Ini.WriteString(Secao, 'Nome', Bancos[I].Nome);
      Ini.WriteString(Secao, 'Arquivo', Bancos[I].Arquivo);
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

function TConfig.Validar(out AErro: string): Boolean;
var
  B: TBancoConfig;
begin
  Result := False;
  AErro := '';
  if not TFile.Exists(Gbak) then
    AErro := 'FirebirdDir: não encontrado gbak.exe em "' + FirebirdDir + '"'
  else if not TFile.Exists(Nbackup) then
    AErro := 'FirebirdDir: não encontrado nbackup.exe em "' + FirebirdDir + '"'
  else if Trim(Usuario) = '' then
    AErro := 'Usuario: informe o usuário do Firebird'
  else if Trim(Destino) = '' then
    AErro := 'Destino: informe a pasta de destino'
  else if RetencaoDias < 1 then
    AErro := 'RetencaoDias: deve ser 1 ou mais'
  else if not HorarioValido(Horario) then
    AErro := 'Horario: use o formato HH:MM (ex.: 02:00)'
  else if not (CopiaFbk or CopiaFdb) then
    AErro := 'Ative ao menos uma cópia (fbk ou fdb)'
  else if Bancos.Count = 0 then
    AErro := 'Informe ao menos um banco';
  if AErro <> '' then
    Exit;
  for B in Bancos do
  begin
    if not NomeValido(B.Nome) then
      Exit(SetErro(AErro, 'Nome do banco "' + B.Nome + '": use só letras, dígitos, "-" e "_"'));
    if not TFile.Exists(B.Arquivo) then
      Exit(SetErro(AErro, 'Banco "' + B.Nome + '": arquivo não encontrado "' + B.Arquivo + '"'));
  end;
  try
    if not TDirectory.Exists(Destino) then
      TDirectory.CreateDirectory(Destino);
  except
    on E: Exception do
      Exit(SetErro(AErro, 'Destino: não foi possível criar "' + Destino + '": ' + E.Message));
  end;
  Result := True;
end;
```

`SetErro` é uma função local da unit (coloque antes de `Validar`):

```pascal
function SetErro(var AErro: string; const AMsg: string): Boolean;
begin
  AErro := AMsg;
  Result := False;
end;
```

`IfThen` para string vem de `System.StrUtils`: acrescentar `System.StrUtils` ao `uses` da implementation.

- [ ] **Step 4: Rodar `testar.cmd`**

Expected: `Tests Passed : 11`, `Tests Failed : 0`, exit 0.

---

### Task 3: `pLog` — log diário em arquivo com evento para a tela

**Files:**
- Create: `src/pLog.pas`, `tests/pTesteLog.pas`
- Modify: `tests/Testes.dpr`

**Interfaces:**
- Produces:
  ```pascal
  TLinhaEvento = reference to procedure(const ALinha: string);
  TLog = class
    constructor Create(const ADestino: string);   // pasta onde ficam os .log
    procedure Escrever(const ATexto: string);     // "hh:nn:ss  texto" no arquivo do dia + OnLinha
    property OnLinha: TLinhaEvento;
    property Agora: TDateTime;                    // injetável; padrão Now (lido a cada Escrever se 0)
    class function NomeArquivo(const ADestino: string; ADia: TDateTime): string; // destino\backup_AAAA-MM-DD.log
  end;
  ```

- [ ] **Step 1: Escrever `tests/pTesteLog.pas`**

```pascal
unit pTesteLog;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Classes, pLog;

type
  [TestFixture]
  TTesteLog = class
  private
    FPasta: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNomeArquivoPorDia;
    [Test] procedure TestEscreverGravaEDispara;
    [Test] procedure TestEscreverAcumulaLinhas;
  end;

implementation

procedure TTesteLog.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_log_' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(FPasta);
end;

procedure TTesteLog.TearDown;
begin
  TDirectory.Delete(FPasta, True);
end;

procedure TTesteLog.TestNomeArquivoPorDia;
begin
  Assert.AreEqual(TPath.Combine('D:\Bk', 'backup_2026-10-05.log'),
    TLog.NomeArquivo('D:\Bk', EncodeDate(2026, 10, 5)));
end;

procedure TTesteLog.TestEscreverGravaEDispara;
var
  L: TLog;
  Recebida: string;
  Conteudo: string;
begin
  L := TLog.Create(FPasta);
  try
    L.Agora := EncodeDate(2026, 10, 5) + EncodeTime(2, 3, 4, 0);
    L.OnLinha := procedure(const ALinha: string) begin Recebida := ALinha; end;
    L.Escrever('Olá');
    Assert.AreEqual('02:03:04  Olá', Recebida);
    Conteudo := TFile.ReadAllText(TLog.NomeArquivo(FPasta, EncodeDate(2026, 10, 5)), TEncoding.UTF8);
    Assert.AreEqual('02:03:04  Olá' + sLineBreak, Conteudo);
  finally
    L.Free;
  end;
end;

procedure TTesteLog.TestEscreverAcumulaLinhas;
var
  L: TLog;
  Linhas: TArray<string>;
begin
  L := TLog.Create(FPasta);
  try
    L.Agora := EncodeDate(2026, 10, 5);
    L.Escrever('a');
    L.Escrever('b');
    Linhas := TFile.ReadAllLines(TLog.NomeArquivo(FPasta, EncodeDate(2026, 10, 5)), TEncoding.UTF8);
    Assert.AreEqual(2, Length(Linhas));
    Assert.EndsWith('b', Linhas[1]);
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteLog);

end.
```

- [ ] **Step 2: Adicionar `pTesteLog` e `pLog` ao `Testes.dpr`; rodar `testar.cmd`** — Expected: falha de compilação.

- [ ] **Step 3: Implementar `src/pLog.pas`**

```pascal
unit pLog;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs;

type
  TLinhaEvento = reference to procedure(const ALinha: string);

  TLog = class
  private
    FDestino: string;
    FAgora: TDateTime;
    FOnLinha: TLinhaEvento;
    FLock: TCriticalSection;
    function Momento: TDateTime;
  public
    constructor Create(const ADestino: string);
    destructor Destroy; override;
    procedure Escrever(const ATexto: string);
    class function NomeArquivo(const ADestino: string; ADia: TDateTime): string;
    property OnLinha: TLinhaEvento read FOnLinha write FOnLinha;
    property Agora: TDateTime read FAgora write FAgora;
  end;

implementation

uses
  System.IOUtils;

constructor TLog.Create(const ADestino: string);
begin
  inherited Create;
  FDestino := ADestino;
  FLock := TCriticalSection.Create;
end;

destructor TLog.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TLog.Momento: TDateTime;
begin
  if FAgora = 0 then
    Result := Now
  else
    Result := FAgora;
end;

class function TLog.NomeArquivo(const ADestino: string; ADia: TDateTime): string;
begin
  Result := TPath.Combine(ADestino, 'backup_' + FormatDateTime('yyyy-mm-dd', ADia) + '.log');
end;

procedure TLog.Escrever(const ATexto: string);
var
  M: TDateTime;
  Linha: string;
begin
  M := Momento;
  Linha := FormatDateTime('hh:nn:ss', M) + '  ' + ATexto;
  FLock.Enter;
  try
    try
      if not TDirectory.Exists(FDestino) then
        TDirectory.CreateDirectory(FDestino);
      TFile.AppendAllText(NomeArquivo(FDestino, M), Linha + sLineBreak, TEncoding.UTF8);
    except
      // Falha ao gravar o log não pode derrubar o backup; a tela ainda recebe a linha.
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnLinha) then
    FOnLinha(Linha);
end;

end.
```

`TFile.AppendAllText` com `TEncoding.UTF8` grava BOM apenas se o arquivo não existe; o teste `TestEscreverGravaEDispara` lê com `ReadAllText(…, UTF8)`, que descarta o BOM. Se o teste falhar por BOM no meio do arquivo, trocar por `TFile.AppendAllText(Arq, Linha + sLineBreak)` sem encoding (ANSI) **e** ler sem encoding no teste; registrar o desvio.

- [ ] **Step 4: Rodar `testar.cmd`** — Expected: `Tests Passed : 14`, exit 0.

---

### Task 4: `pProcesso` — executar utilitário com pipe de saída e ambiente próprio

**Files:**
- Create: `src/pProcesso.pas`, `tests/pTesteProcesso.pas`
- Modify: `tests/Testes.dpr`

**Interfaces:**
- Consumes: `TLinhaEvento` de `pLog`.
- Produces:
  ```pascal
  TExecutor = reference to function(const AExe, AArgs: string; AAmbiente: TStrings;
    AOnLinha: TLinhaEvento): Integer;   // retorna ExitCode do processo
  EProcesso = class(Exception);
  function ExecutarProcesso(const AExe, AArgs: string; AAmbiente: TStrings;
    AOnLinha: TLinhaEvento): Integer;   // levanta EProcesso se CreateProcess falhar
  function Aspas(const S: string): string;   // "S" (sempre entre aspas duplas)
  ```
  `AAmbiente` é uma lista `NOME=VALOR` acrescentada ao ambiente atual do processo pai (pode ser `nil`).

- [ ] **Step 1: Escrever `tests/pTesteProcesso.pas`**

```pascal
unit pTesteProcesso;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, pProcesso;

type
  [TestFixture]
  TTesteProcesso = class
  private
    function Cmd: string;
  public
    [Test] procedure TestCapturaStdoutEExitCode;
    [Test] procedure TestCapturaStderr;
    [Test] procedure TestAmbienteChegaAoFilho;
    [Test] procedure TestExeInexistenteLevantaExcecao;
    [Test] procedure TestSaidaOemConvertida;
    [Test] procedure TestAspas;
  end;

implementation

uses
  Winapi.Windows;

function TTesteProcesso.Cmd: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
end;

procedure TTesteProcesso.TestCapturaStdoutEExitCode;
var
  Linhas: TStringList;
  Codigo: Integer;
begin
  Linhas := TStringList.Create;
  try
    Codigo := ExecutarProcesso(Cmd, '/c "echo um& echo dois& exit 3"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual(3, Codigo);
    Assert.AreEqual(2, Linhas.Count);
    Assert.AreEqual('um', Linhas[0]);
    Assert.AreEqual('dois', Linhas[1]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestCapturaStderr;
var
  Linhas: TStringList;
begin
  Linhas := TStringList.Create;
  try
    ExecutarProcesso(Cmd, '/c "echo erro 1>&2"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual(1, Linhas.Count);
    Assert.AreEqual('erro', Linhas[0]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestAmbienteChegaAoFilho;
var
  Linhas, Amb: TStringList;
begin
  Linhas := TStringList.Create;
  Amb := TStringList.Create;
  try
    Amb.Add('ISC_USER=TESTE_USR');
    ExecutarProcesso(Cmd, '/c "echo %ISC_USER%-%ComSpec%"', Amb,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual(1, Linhas.Count);
    Assert.StartsWith('TESTE_USR-', Linhas[0]);
    Assert.IsFalse(Linhas[0].EndsWith('%ComSpec%'), 'ambiente do pai deve ser herdado');
  finally
    Linhas.Free;
    Amb.Free;
  end;
end;

procedure TTesteProcesso.TestExeInexistenteLevantaExcecao;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecutarProcesso('C:\nao\existe\gbak.exe', '-b', nil, nil);
    end, EProcesso);
end;

procedure TTesteProcesso.TestSaidaOemConvertida;
var
  Linhas: TStringList;
begin
  // cmd.exe escreve na codepage OEM (850/437); "ção" precisa chegar legível.
  Linhas := TStringList.Create;
  try
    ExecutarProcesso(Cmd, '/c "echo ação"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual('ação', Linhas[0]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestAspas;
begin
  Assert.AreEqual('"C:\Program Files\x.exe"', Aspas('C:\Program Files\x.exe'));
  Assert.AreEqual('""', Aspas(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteProcesso);

end.
```

Nota sobre `TestSaidaOemConvertida`: o `.pas` é UTF-8 com BOM, então o literal `'ação'` passa ao `cmd` como UTF-16 → Delphi converte os argumentos para ANSI do sistema (1252) ao chamar `CreateProcessW`? Não: `CreateProcessW` recebe UTF-16 e `cmd` escreve `ação` na codepage OEM do console (850). Por isso a implementação converte OEM→ANSI com `OemToCharBuffA` antes de virar `string`.

- [ ] **Step 2: Adicionar ao `Testes.dpr`; rodar `testar.cmd`** — Expected: falha de compilação.

- [ ] **Step 3: Implementar `src/pProcesso.pas`**

```pascal
unit pProcesso;

interface

uses
  System.SysUtils, System.Classes, pLog;

type
  EProcesso = class(Exception);

  TExecutor = reference to function(const AExe, AArgs: string; AAmbiente: TStrings;
    AOnLinha: TLinhaEvento): Integer;

function ExecutarProcesso(const AExe, AArgs: string; AAmbiente: TStrings;
  AOnLinha: TLinhaEvento): Integer;
function Aspas(const S: string): string;

implementation

uses
  Winapi.Windows;

function Aspas(const S: string): string;
begin
  Result := '"' + S + '"';
end;

// Bloco de ambiente = ambiente atual + entradas de AAmbiente (sobrescrevendo as de mesmo nome).
function MontarAmbiente(AAmbiente: TStrings): string;
var
  P, Inicio: PChar;
  Lista: TStringList;
  I, J: Integer;
  Nome: string;
begin
  Lista := TStringList.Create;
  try
    P := GetEnvironmentStrings;
    try
      Inicio := P;
      while P^ <> #0 do
      begin
        Lista.Add(P);
        Inc(P, StrLen(P) + 1);
      end;
      FreeEnvironmentStrings(Inicio);
    except
      FreeEnvironmentStrings(Inicio);
      raise;
    end;
    if Assigned(AAmbiente) then
      for I := 0 to AAmbiente.Count - 1 do
      begin
        Nome := AAmbiente.Names[I];
        for J := Lista.Count - 1 downto 0 do
          if SameText(Lista.Names[J], Nome) then
            Lista.Delete(J);
        Lista.Add(AAmbiente[I]);
      end;
    Result := '';
    for I := 0 to Lista.Count - 1 do
      Result := Result + Lista[I] + #0;
    Result := Result + #0;
  finally
    Lista.Free;
  end;
end;

function ExecutarProcesso(const AExe, AArgs: string; AAmbiente: TStrings;
  AOnLinha: TLinhaEvento): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  LeituraPipe, EscritaPipe: THandle;
  Linha: string;
  Ambiente: string;
  Buffer: array[0..4095] of AnsiChar;
  Lidos: DWORD;
  Pendente, Trecho: AnsiString;
  Codigo: DWORD;

  procedure EmitirLinha(const ABytes: AnsiString);
  var
    Convertida: AnsiString;
  begin
    SetLength(Convertida, Length(ABytes));
    if Length(ABytes) > 0 then
      OemToCharBuffA(PAnsiChar(ABytes), PAnsiChar(Convertida), Length(ABytes));
    Linha := string(Convertida);
    if (Linha <> '') and (Linha[Length(Linha)] = #13) then
      SetLength(Linha, Length(Linha) - 1);
    if Assigned(AOnLinha) then
      AOnLinha(Linha);
  end;

  procedure ProcessarPendente(AFinal: Boolean);
  var
    Pos: Integer;
  begin
    Pos := System.Pos(AnsiString(#10), Pendente);
    while Pos > 0 do
    begin
      EmitirLinha(Copy(Pendente, 1, Pos - 1));
      Delete(Pendente, 1, Pos);
      Pos := System.Pos(AnsiString(#10), Pendente);
    end;
    if AFinal and (Pendente <> '') then
    begin
      EmitirLinha(Pendente);
      Pendente := '';
    end;
  end;

begin
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  if not CreatePipe(LeituraPipe, EscritaPipe, @SA, 0) then
    raise EProcesso.Create('CreatePipe: ' + SysErrorMessage(GetLastError));
  try
    SetHandleInformation(LeituraPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := EscritaPipe;
    SI.hStdError := EscritaPipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    Ambiente := MontarAmbiente(AAmbiente);
    Linha := Aspas(AExe) + ' ' + AArgs;
    UniqueString(Linha);
    if not CreateProcess(PChar(AExe), PChar(Linha), nil, nil, True,
      CREATE_NO_WINDOW or BELOW_NORMAL_PRIORITY_CLASS or CREATE_UNICODE_ENVIRONMENT,
      PChar(Ambiente), nil, SI, PI) then
      raise EProcesso.Create('Não foi possível executar "' + AExe + '": ' +
        SysErrorMessage(GetLastError));
    CloseHandle(EscritaPipe);
    EscritaPipe := 0;
    try
      Pendente := '';
      while ReadFile(LeituraPipe, Buffer, SizeOf(Buffer), Lidos, nil) and (Lidos > 0) do
      begin
        SetString(Trecho, PAnsiChar(@Buffer[0]), Lidos);
        Pendente := Pendente + Trecho;
        ProcessarPendente(False);
      end;
      ProcessarPendente(True);
      WaitForSingleObject(PI.hProcess, INFINITE);
      if not GetExitCodeProcess(PI.hProcess, Codigo) then
        Codigo := DWORD(-1);
      Result := Integer(Codigo);
    finally
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
    end;
  finally
    if EscritaPipe <> 0 then
      CloseHandle(EscritaPipe);
    CloseHandle(LeituraPipe);
  end;
end;

end.
```

`SetString` com o tamanho lido evita cortar o buffer em um `#0`.

- [ ] **Step 4: Rodar `testar.cmd`** — Expected: `Tests Passed : 20`, exit 0.

---

### Task 5: `pBackup` parte 1 — nomes de arquivo, retenção e status

**Files:**
- Create: `src/pBackup.pas`, `tests/pTesteBackup.pas`
- Modify: `tests/Testes.dpr`

**Interfaces:**
- Consumes: `TConfig`, `TBancoConfig` (Task 2), `TLog` (Task 3), `TExecutor`, `ExecutarProcesso`, `Aspas` (Task 4).
- Produces (parte 1):
  ```pascal
  TResultadoBanco = record
    Nome: string; Inicio, Fim: TDateTime; OK: Boolean; Mensagem: string;
    TamanhoFbk, TamanhoFdb: Int64;
  end;
  TBackup = class
    constructor Create(AConfig: TConfig; ALog: TLog; AExecutor: TExecutor = nil);
    property Agora: TDateTime;   // injetável; 0 = Now
    class function NomeArquivoBackup(const ADestino, ANome: string; AQuando: TDateTime; const AExt: string): string;
      // destino\NOME_AAAA-MM-DD_HHMM.ext
    class function CasaPadraoRetencao(const ANomeArquivo: string; const ANomes: TArray<string>): Boolean;
      // NOME_AAAA-MM-DD_HHMM.fbk|.fdb (NOME em ANomes, case-insensitive) ou backup_AAAA-MM-DD.log
    procedure AplicarRetencao;   // apaga no Destino o que casa e tem LastWriteTime < Agora - RetencaoDias
    procedure GravarStatus(const AResultados: TArray<TResultadoBanco>);
      // destino\ultimo-status.ini: [Geral] UltimaExecucao=yyyy-mm-dd hh:nn:ss, Resultado=OK|ERRO; [NOME] Inicio, Fim, DuracaoSeg, Resultado, Mensagem, TamanhoFbk, TamanhoFdb
    class function LerUltimaExecucao(const ADestino: string): TDateTime; // 0 se não há status
  end;
  ```

- [ ] **Step 1: Escrever `tests/pTesteBackup.pas` (parte 1)**

```pascal
unit pTesteBackup;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  pConfig, pLog, pBackup;

type
  [TestFixture]
  TTesteBackup = class
  private
    FPasta, FDestino, FFb: string;
    FConfig: TConfig;
    FLog: TLog;
    procedure CriarArquivo(const ANome: string; ADataModif: TDateTime; ATamanho: Integer = 0);
    procedure AddBanco(const ANome: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNomeArquivoBackup;
    [Test] procedure TestCasaPadraoRetencao;
    [Test] procedure TestRetencaoApagaSoAntigosNoPadrao;
    [Test] procedure TestGravarELerStatus;
  end;

implementation

procedure TTesteBackup.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_bk_' + TPath.GetGUIDFileName);
  FDestino := TPath.Combine(FPasta, 'dest');
  FFb := TPath.Combine(FPasta, 'fb');
  TDirectory.CreateDirectory(FDestino);
  TDirectory.CreateDirectory(FFb);
  TFile.WriteAllText(TPath.Combine(FFb, 'gbak.exe'), '');
  TFile.WriteAllText(TPath.Combine(FFb, 'nbackup.exe'), '');
  FConfig := TConfig.Create;
  FConfig.FirebirdDir := FFb;
  FConfig.Destino := FDestino;
  FConfig.Senha := 'segredo';
  FLog := TLog.Create(FDestino);
end;

procedure TTesteBackup.TearDown;
begin
  FLog.Free;
  FConfig.Free;
  TDirectory.Delete(FPasta, True);
end;

procedure TTesteBackup.CriarArquivo(const ANome: string; ADataModif: TDateTime; ATamanho: Integer);
var
  Arq: string;
begin
  Arq := TPath.Combine(FDestino, ANome);
  TFile.WriteAllText(Arq, StringOfChar('x', ATamanho));
  TFile.SetLastWriteTime(Arq, ADataModif);
end;

procedure TTesteBackup.AddBanco(const ANome: string);
var
  B: TBancoConfig;
begin
  B.Nome := ANome;
  B.Arquivo := TPath.Combine(FPasta, ANome + '.FDB');
  TFile.WriteAllText(B.Arquivo, 'db');
  FConfig.Bancos.Add(B);
end;

procedure TTesteBackup.TestNomeArquivoBackup;
begin
  Assert.AreEqual('D:\Bk\AG2006_2026-10-05_0200.fbk',
    TBackup.NomeArquivoBackup('D:\Bk', 'AG2006', EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 7, 0), '.fbk'));
end;

procedure TTesteBackup.TestCasaPadraoRetencao;
var
  Nomes: TArray<string>;
begin
  Nomes := ['AG2006', 'Outro'];
  Assert.IsTrue(TBackup.CasaPadraoRetencao('AG2006_2026-10-05_0200.fbk', Nomes));
  Assert.IsTrue(TBackup.CasaPadraoRetencao('ag2006_2026-10-05_0200.FDB', Nomes));
  Assert.IsTrue(TBackup.CasaPadraoRetencao('backup_2026-10-05.log', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006.FDB', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006_2026-10-05_0200.rar', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('XYZ_2026-10-05_0200.fbk', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006_2026-10-05.fbk', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('ultimo-status.ini', Nomes));
end;

procedure TTesteBackup.TestRetencaoApagaSoAntigosNoPadrao;
var
  Bk: TBackup;
  Hoje: TDateTime;
begin
  AddBanco('AG');
  FConfig.RetencaoDias := 7;
  Hoje := EncodeDate(2026, 10, 20);
  CriarArquivo('AG_2026-10-01_0200.fbk', Hoje - 19);    // apaga
  CriarArquivo('AG_2026-10-12_0200.fdb', Hoje - 8);     // apaga
  CriarArquivo('AG_2026-10-14_0200.fbk', Hoje - 6);     // mantém
  CriarArquivo('backup_2026-10-01.log', Hoje - 19);      // apaga
  CriarArquivo('OUTRO_2026-10-01_0200.fbk', Hoje - 19);  // mantém: banco não configurado
  CriarArquivo('importante.txt', Hoje - 30);             // mantém
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := Hoje;
    Bk.AplicarRetencao;
  finally
    Bk.Free;
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-01_0200.fbk')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-12_0200.fdb')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'backup_2026-10-01.log')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-14_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'OUTRO_2026-10-01_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'importante.txt')));
end;

procedure TTesteBackup.TestGravarELerStatus;
var
  Bk: TBackup;
  R: TArray<TResultadoBanco>;
  Ini: TIniFile;
begin
  AddBanco('AG');
  SetLength(R, 2);
  R[0].Nome := 'AG'; R[0].Inicio := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
  R[0].Fim := R[0].Inicio + EncodeTime(0, 1, 30, 0); R[0].OK := True; R[0].Mensagem := '';
  R[0].TamanhoFbk := 1234; R[0].TamanhoFdb := 5678;
  R[1].Nome := 'XY'; R[1].Inicio := R[0].Fim; R[1].Fim := R[0].Fim; R[1].OK := False;
  R[1].Mensagem := 'falhou';
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := R[0].Inicio;
    Bk.GravarStatus(R);
  finally
    Bk.Free;
  end;
  Ini := TIniFile.Create(TPath.Combine(FDestino, 'ultimo-status.ini'));
  try
    Assert.AreEqual('ERRO', Ini.ReadString('Geral', 'Resultado', ''));
    Assert.AreEqual('2026-10-05 02:00:00', Ini.ReadString('Geral', 'UltimaExecucao', ''));
    Assert.AreEqual('OK', Ini.ReadString('AG', 'Resultado', ''));
    Assert.AreEqual(90, Ini.ReadInteger('AG', 'DuracaoSeg', -1));
    Assert.AreEqual('1234', Ini.ReadString('AG', 'TamanhoFbk', ''));
    Assert.AreEqual('falhou', Ini.ReadString('XY', 'Mensagem', ''));
  finally
    Ini.Free;
  end;
  Assert.AreEqual(R[0].Inicio, TBackup.LerUltimaExecucao(FDestino), 0.00001);
  Assert.AreEqual(0.0, TBackup.LerUltimaExecucao(TPath.Combine(FPasta, 'vazio')), 0.00001);
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteBackup);

end.
```

- [ ] **Step 2: Adicionar ao `Testes.dpr`; rodar** — Expected: falha de compilação.

- [ ] **Step 3: Implementar `src/pBackup.pas` (parte 1; a parte 2 na Task 6 acrescenta `Executar`/`ExecutarBanco`)**

```pascal
unit pBackup;

interface

uses
  System.SysUtils, System.Classes, pConfig, pLog, pProcesso;

type
  TResultadoBanco = record
    Nome: string;
    Inicio: TDateTime;
    Fim: TDateTime;
    OK: Boolean;
    Mensagem: string;
    TamanhoFbk: Int64;
    TamanhoFdb: Int64;
  end;

  TBackup = class
  private
    FConfig: TConfig;
    FLog: TLog;
    FExecutor: TExecutor;
    FAgora: TDateTime;
    function Momento: TDateTime;
    function NomesBancos: TArray<string>;
  public
    constructor Create(AConfig: TConfig; ALog: TLog; AExecutor: TExecutor = nil);
    procedure AplicarRetencao;
    procedure GravarStatus(const AResultados: TArray<TResultadoBanco>);
    class function NomeArquivoBackup(const ADestino, ANome: string; AQuando: TDateTime;
      const AExt: string): string;
    class function CasaPadraoRetencao(const ANomeArquivo: string;
      const ANomes: TArray<string>): Boolean;
    class function LerUltimaExecucao(const ADestino: string): TDateTime;
    property Agora: TDateTime read FAgora write FAgora;
  end;

implementation

uses
  System.IOUtils, System.IniFiles, System.StrUtils, System.DateUtils, System.Character;

constructor TBackup.Create(AConfig: TConfig; ALog: TLog; AExecutor: TExecutor);
begin
  inherited Create;
  FConfig := AConfig;
  FLog := ALog;
  if Assigned(AExecutor) then
    FExecutor := AExecutor
  else
    FExecutor := ExecutarProcesso;
end;

function TBackup.Momento: TDateTime;
begin
  if FAgora = 0 then
    Result := Now
  else
    Result := FAgora;
end;

function TBackup.NomesBancos: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FConfig.Bancos.Count);
  for I := 0 to FConfig.Bancos.Count - 1 do
    Result[I] := FConfig.Bancos[I].Nome;
end;

class function TBackup.NomeArquivoBackup(const ADestino, ANome: string; AQuando: TDateTime;
  const AExt: string): string;
begin
  Result := TPath.Combine(ADestino, ANome + '_' + FormatDateTime('yyyy-mm-dd_hhnn', AQuando) + AExt);
end;

// Verifica "AAAA-MM-DD" em S a partir de Pos (1-based)
function EhData(const S: string; APos: Integer): Boolean;
const
  Mascara = 'NNNN-NN-NN';
var
  I: Integer;
begin
  if Length(S) < APos + Length(Mascara) - 1 then
    Exit(False);
  for I := 1 to Length(Mascara) do
    if Mascara[I] = 'N' then
    begin
      if not S[APos + I - 1].IsDigit then
        Exit(False);
    end
    else if S[APos + I - 1] <> Mascara[I] then
      Exit(False);
  Result := True;
end;

function EhHoraHHNN(const S: string; APos: Integer): Boolean;
var
  I: Integer;
begin
  if Length(S) < APos + 3 then
    Exit(False);
  for I := 0 to 3 do
    if not S[APos + I].IsDigit then
      Exit(False);
  Result := True;
end;

class function TBackup.CasaPadraoRetencao(const ANomeArquivo: string;
  const ANomes: TArray<string>): Boolean;
var
  Ext, Base, Nome: string;
  P: Integer;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(ANomeArquivo));
  Base := ChangeFileExt(ANomeArquivo, '');
  if Ext = '.log' then
    // backup_AAAA-MM-DD
    Exit((Length(Base) = 17) and StartsText('backup_', Base) and EhData(Base, 8));
  if (Ext <> '.fbk') and (Ext <> '.fdb') then
    Exit;
  // NOME_AAAA-MM-DD_HHNN  => sufixo de 16 chars: _AAAA-MM-DD_HHNN
  if Length(Base) < 17 then
    Exit;
  P := Length(Base) - 15;              // posição do '_' antes da data
  if Base[P] <> '_' then
    Exit;
  if not EhData(Base, P + 1) then
    Exit;
  if Base[P + 11] <> '_' then
    Exit;
  if not EhHoraHHNN(Base, P + 12) then
    Exit;
  for Nome in ANomes do
    if SameText(Copy(Base, 1, P - 1), Nome) then
      Exit(True);
end;

procedure TBackup.AplicarRetencao;
var
  Limite: TDateTime;
  Arq: string;
  Nomes: TArray<string>;
begin
  Limite := Momento - FConfig.RetencaoDias;
  Nomes := NomesBancos;
  if not TDirectory.Exists(FConfig.Destino) then
    Exit;
  for Arq in TDirectory.GetFiles(FConfig.Destino) do
    if CasaPadraoRetencao(ExtractFileName(Arq), Nomes)
      and (TFile.GetLastWriteTime(Arq) < Limite) then
    begin
      try
        TFile.Delete(Arq);
        FLog.Escrever('Retenção: apagado ' + ExtractFileName(Arq));
      except
        on E: Exception do
          FLog.Escrever('Retenção: não foi possível apagar ' + ExtractFileName(Arq) + ': ' + E.Message);
      end;
    end;
end;

procedure TBackup.GravarStatus(const AResultados: TArray<TResultadoBanco>);
var
  Ini: TIniFile;
  R: TResultadoBanco;
  Todos: Boolean;
begin
  Todos := True;
  for R in AResultados do
    Todos := Todos and R.OK;
  Ini := TIniFile.Create(TPath.Combine(FConfig.Destino, 'ultimo-status.ini'));
  try
    Ini.WriteString('Geral', 'UltimaExecucao', FormatDateTime('yyyy-mm-dd hh:nn:ss', Momento));
    Ini.WriteString('Geral', 'Resultado', IfThen(Todos, 'OK', 'ERRO'));
    for R in AResultados do
    begin
      Ini.WriteString(R.Nome, 'Inicio', FormatDateTime('yyyy-mm-dd hh:nn:ss', R.Inicio));
      Ini.WriteString(R.Nome, 'Fim', FormatDateTime('yyyy-mm-dd hh:nn:ss', R.Fim));
      Ini.WriteInteger(R.Nome, 'DuracaoSeg', SecondsBetween(R.Fim, R.Inicio));
      Ini.WriteString(R.Nome, 'Resultado', IfThen(R.OK, 'OK', 'ERRO'));
      Ini.WriteString(R.Nome, 'Mensagem', R.Mensagem);
      Ini.WriteString(R.Nome, 'TamanhoFbk', IntToStr(R.TamanhoFbk));
      Ini.WriteString(R.Nome, 'TamanhoFdb', IntToStr(R.TamanhoFdb));
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TBackup.LerUltimaExecucao(const ADestino: string): TDateTime;
var
  Ini: TIniFile;
  S: string;
  Fmt: TFormatSettings;
begin
  Result := 0;
  if not TFile.Exists(TPath.Combine(ADestino, 'ultimo-status.ini')) then
    Exit;
  Ini := TIniFile.Create(TPath.Combine(ADestino, 'ultimo-status.ini'));
  try
    S := Ini.ReadString('Geral', 'UltimaExecucao', '');
  finally
    Ini.Free;
  end;
  Fmt := TFormatSettings.Create;
  Fmt.DateSeparator := '-';
  Fmt.TimeSeparator := ':';
  Fmt.ShortDateFormat := 'yyyy-mm-dd';
  Fmt.LongTimeFormat := 'hh:nn:ss';
  if not TryStrToDateTime(S, Result, Fmt) then
    Result := 0;
end;

end.
```

- [ ] **Step 4: Rodar `testar.cmd`** — Expected: `Tests Passed : 24`, exit 0.

---

### Task 6: `pBackup` parte 2 — sequência gbak/nbackup por banco com executor falso

**Files:**
- Modify: `src/pBackup.pas`, `tests/pTesteBackup.pas`

**Interfaces:**
- Produces:
  ```pascal
  TBackup.Executar: Boolean;                           // roda todos os bancos, retenção, status; True se todos OK
  TBackup.ExecutarBanco(const ABanco: TBancoConfig): TResultadoBanco;
  TBackup.EspacoLivre(const APasta: string): Int64;    // virtual; GetDiskFreeSpaceEx; testes sobrescrevem via propriedade EspacoLivreFixo
  property EspacoLivreFixo: Int64;                     // -1 = usar o real
  property Cancelado: Boolean;                         // reservado; não usado na v1
  ```
- Comandos exatos gerados (todos os caminhos entre aspas via `Aspas`):
  - gbak: `-b -g -v -se localhost:service_mgr "<arquivo>" "<destino>\NOME_data.fbk"`
  - lock: `-L "<arquivo>"`; unlock: `-N "<arquivo>"`; fixup: `-F "<cópia>"`
  - Ambiente de todos: `ISC_USER=<Usuario>`, `ISC_PASSWORD=<Senha>`
- Marcador de lock: `<destino>\<NOME>.lock-pendente`.

- [ ] **Step 1: Acrescentar testes em `tests/pTesteBackup.pas`**

Adicionar ao `private` da fixture:

```pascal
    FChamadas: TStringList;      // "exe|args"
    FAmbientes: TStringList;     // "ISC_USER=..;ISC_PASSWORD=.." por chamada
    FCodigos: TDictionary<string, Integer>; // prefixo de args -> exit code (padrão 0)
    function ExecutorFalso: TExecutor;
    function Chamada(I: Integer): string;
```

`uses` da interface ganha `System.Generics.Collections, pProcesso`. Em `Setup` criar `FChamadas`, `FAmbientes`, `FCodigos`; em `TearDown` liberar. Implementação do executor falso:

```pascal
function TTesteBackup.ExecutorFalso: TExecutor;
begin
  Result := function(const AExe, AArgs: string; AAmbiente: TStrings; AOnLinha: TLinhaEvento): Integer
    var
      Chave: string;
      Destino: string;
    begin
      FChamadas.Add(ExtractFileName(AExe) + '|' + AArgs);
      if Assigned(AAmbiente) then
        FAmbientes.Add(AAmbiente.Values['ISC_USER'] + ';' + AAmbiente.Values['ISC_PASSWORD'])
      else
        FAmbientes.Add('');
      if Assigned(AOnLinha) then
        AOnLinha('saida ' + Copy(AArgs, 1, 2));
      // gbak -b: simula criando o arquivo de saída (último argumento entre aspas)
      if SameText(ExtractFileName(AExe), 'gbak.exe') then
      begin
        Destino := AArgs;
        Delete(Destino, 1, LastDelimiter('"', Copy(Destino, 1, Length(Destino) - 1)));
        Destino := Copy(Destino, 1, Length(Destino) - 1);
        TFile.WriteAllText(Destino, 'fbk-falso');
      end;
      Result := 0;
      for Chave in FCodigos.Keys do
        if StartsText(Chave, ExtractFileName(AExe) + '|' + AArgs) then
          Result := FCodigos[Chave];
    end;
end;

function TTesteBackup.Chamada(I: Integer): string;
begin
  if I < FChamadas.Count then
    Result := FChamadas[I]
  else
    Result := '<nenhuma>';
end;
```

Novos testes (declarar em `public` com `[Test]`):

```pascal
procedure TTesteBackup.TestSequenciaCompletaOk;
var
  Bk: TBackup;
  R: TResultadoBanco;
  Arq, Fbk, Fdb: string;
begin
  AddBanco('AG');
  Arq := FConfig.Bancos[0].Arquivo;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.Agora := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Fbk := TPath.Combine(FDestino, 'AG_2026-10-05_0200.fbk');
  Fdb := TPath.Combine(FDestino, 'AG_2026-10-05_0200.fdb');
  Assert.IsTrue(R.OK, R.Mensagem);
  Assert.AreEqual(4, FChamadas.Count);
  Assert.AreEqual('gbak.exe|-b -g -v -se localhost:service_mgr "' + Arq + '" "' + Fbk + '"', Chamada(0));
  Assert.AreEqual('nbackup.exe|-L "' + Arq + '"', Chamada(1));
  Assert.AreEqual('nbackup.exe|-N "' + Arq + '"', Chamada(2));
  Assert.AreEqual('nbackup.exe|-F "' + Fdb + '"', Chamada(3));
  Assert.AreEqual('SYSDBA;segredo', FAmbientes[0]);
  Assert.AreEqual('SYSDBA;segredo', FAmbientes[1]);
  Assert.IsTrue(TFile.Exists(Fbk));
  Assert.IsTrue(TFile.Exists(Fdb), 'cópia física deve existir');
  Assert.AreEqual('db', TFile.ReadAllText(Fdb));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
  Assert.AreEqual(Int64(9), R.TamanhoFbk);
  Assert.AreEqual(Int64(2), R.TamanhoFdb);
end;

procedure TTesteBackup.TestComandoGbakComEspacos;
var
  Bk: TBackup;
  B: TBancoConfig;
  Dir: string;
begin
  Dir := TPath.Combine(FPasta, 'com espaco');
  TDirectory.CreateDirectory(Dir);
  B.Nome := 'AG'; B.Arquivo := TPath.Combine(Dir, 'AG.FDB');
  TFile.WriteAllText(B.Arquivo, 'db');
  FConfig.Bancos.Add(B);
  FConfig.CopiaFdb := False;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := High(Int64);
    Bk.ExecutarBanco(B);
  finally
    Bk.Free;
  end;
  Assert.Contains(Chamada(0), '"' + B.Arquivo + '"');
end;

procedure TTesteBackup.TestSoFbkQuandoFdbDesligado;
var
  Bk: TBackup;
begin
  AddBanco('AG');
  FConfig.CopiaFdb := False;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsTrue(Bk.ExecutarBanco(FConfig.Bancos[0]).OK);
  finally
    Bk.Free;
  end;
  Assert.AreEqual(1, FChamadas.Count);
  Assert.StartsWith('gbak.exe|', Chamada(0));
end;

procedure TTesteBackup.TestGbakFalhaRegistraEContinuaFdb;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');
  FCodigos.Add('gbak.exe|', 1);
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsFalse(R.OK);
  Assert.Contains(R.Mensagem, 'gbak');
  Assert.AreEqual(4, FChamadas.Count, 'cópia fdb ainda roda');
end;

procedure TTesteBackup.TestLockFalhaNaoCopiaNemDestrava;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  FCodigos.Add('nbackup.exe|-L', 1);
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsFalse(R.OK);
  Assert.AreEqual(1, FChamadas.Count);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestCopiaFalhaAindaDestrava;
var
  Bk: TBackup;
  R: TResultadoBanco;
  Fdb: string;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  // Forçar falha da cópia: o destino já existe como somente leitura (CopyFile dá acesso negado)
  Fdb := TPath.Combine(FDestino, 'AG_2026-10-05_0200.fdb');
  TFile.WriteAllText(Fdb, 'velho');
  TFile.SetAttributes(Fdb, [TFileAttribute.faReadOnly]);
  try
    Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
    try
      Bk.Agora := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
      Bk.EspacoLivreFixo := High(Int64);
      R := Bk.ExecutarBanco(FConfig.Bancos[0]);
    finally
      Bk.Free;
    end;
  finally
    TFile.SetAttributes(Fdb, [TFileAttribute.faNormal]);
  end;
  Assert.IsFalse(R.OK);
  Assert.Contains(R.Mensagem, 'cópia');
  Assert.AreEqual('nbackup.exe|-L "' + FConfig.Bancos[0].Arquivo + '"', Chamada(0));
  Assert.AreEqual('nbackup.exe|-N "' + FConfig.Bancos[0].Arquivo + '"', Chamada(1));
  Assert.AreEqual(2, FChamadas.Count, 'sem -F quando a cópia falhou');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestLockPendenteDestravaAntes;
var
  Bk: TBackup;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  TFile.WriteAllText(TPath.Combine(FDestino, 'AG.lock-pendente'), '');
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsTrue(Bk.ExecutarBanco(FConfig.Bancos[0]).OK);
  finally
    Bk.Free;
  end;
  Assert.AreEqual('nbackup.exe|-N "' + FConfig.Bancos[0].Arquivo + '"', Chamada(0));
  Assert.AreEqual('nbackup.exe|-L "' + FConfig.Bancos[0].Arquivo + '"', Chamada(1));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestLockPendenteOrfaoNaoAborta;
var
  Bk: TBackup;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  TFile.WriteAllText(TPath.Combine(FDestino, 'AG.lock-pendente'), '');
  FCodigos.Add('nbackup.exe|-N', 1);   // banco não estava travado: -N falha
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := High(Int64);
    // o -N da recuperação falha (aviso); o -N normal depois do -L também "falha" aqui,
    // então o resultado é ERRO, mas a sequência completa precisa ter rodado
    Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.AreEqual(3, FChamadas.Count);
  Assert.StartsWith('nbackup.exe|-N', Chamada(0));
  Assert.StartsWith('nbackup.exe|-L', Chamada(1));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')),
    'o -N normal falhou: marcador fica para nova tentativa na próxima execução');
end;

procedure TTesteBackup.TestEspacoInsuficientePulaBanco;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');   // arquivo tem 2 bytes; exige 4 com as duas cópias
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.EspacoLivreFixo := 3;
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsFalse(R.OK);
  Assert.Contains(R.Mensagem, 'spaço');
  Assert.AreEqual(0, FChamadas.Count);
end;

procedure TTesteBackup.TestExecutarTodosGravaStatusERetencao;
var
  Bk: TBackup;
  Hoje: TDateTime;
begin
  AddBanco('AG');
  AddBanco('XY');
  FConfig.CopiaFdb := False;
  FConfig.RetencaoDias := 7;
  Hoje := EncodeDate(2026, 10, 20) + EncodeTime(2, 0, 0, 0);
  CriarArquivo('AG_2026-10-01_0200.fbk', Hoje - 19);
  FCodigos.Add('gbak.exe|-b -g -v -se localhost:service_mgr "' + FConfig.Bancos[1].Arquivo, 1);
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.Agora := Hoje;
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsFalse(Bk.Executar, 'XY falhou, resultado geral ERRO');
  finally
    Bk.Free;
  end;
  Assert.AreEqual(2, FChamadas.Count);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-01_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-20_0200.fbk')));
  Assert.AreEqual(Hoje, TBackup.LerUltimaExecucao(FDestino), 0.00001);
end;

procedure TTesteBackup.TestSenhaNaoVaiParaOLog;
var
  Bk: TBackup;
  Texto: string;
begin
  AddBanco('AG');
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso);
  try
    Bk.Agora := EncodeDate(2026, 10, 5);
    Bk.EspacoLivreFixo := High(Int64);
    Bk.Executar;
  finally
    Bk.Free;
  end;
  Texto := TFile.ReadAllText(TLog.NomeArquivo(FDestino, EncodeDate(2026, 10, 5)));
  Assert.DoesNotContain(Texto, 'segredo');
  Assert.Contains(Texto, 'gbak');
end;
```

- [ ] **Step 2: Rodar `testar.cmd`** — Expected: falha de compilação (`ExecutarBanco`, `EspacoLivreFixo` inexistentes).

- [ ] **Step 3: Implementar a parte 2 em `src/pBackup.pas`**

Acrescentar à classe:

```pascal
  private
    FEspacoLivreFixo: Int64;
    function Ambiente: TStrings;
    function Rodar(const AExe, AArgs: string; out AUltimaLinha: string): Integer;
    function MarcadorLock(const ANome: string): string;
    function CopiarArquivo(const AOrigem, ADestino: string; out AErro: string): Boolean;
  public
    function Executar: Boolean;
    function ExecutarBanco(const ABanco: TBancoConfig): TResultadoBanco;
    function EspacoLivre(const APasta: string): Int64; virtual;
    property EspacoLivreFixo: Int64 read FEspacoLivreFixo write FEspacoLivreFixo;
```

No `Create`, `FEspacoLivreFixo := -1`. Implementação:

```pascal
function TBackup.Ambiente: TStrings;
begin
  Result := TStringList.Create;
  Result.Add('ISC_USER=' + FConfig.Usuario);
  Result.Add('ISC_PASSWORD=' + FConfig.Senha);
end;

function TBackup.Rodar(const AExe, AArgs: string; out AUltimaLinha: string): Integer;
var
  Amb: TStrings;
  Ultima: string;
begin
  FLog.Escrever('> ' + ExtractFileName(AExe) + ' ' + AArgs);
  Ultima := '';
  Amb := Ambiente;
  try
    Result := FExecutor(AExe, AArgs, Amb,
      procedure(const L: string)
      begin
        if Trim(L) <> '' then
        begin
          Ultima := L;
          FLog.Escrever('  ' + L);
        end;
      end);
  finally
    Amb.Free;
  end;
  AUltimaLinha := Ultima;
  FLog.Escrever('  código de saída ' + IntToStr(Result));
end;

function TBackup.MarcadorLock(const ANome: string): string;
begin
  Result := TPath.Combine(FConfig.Destino, ANome + '.lock-pendente');
end;

function TBackup.EspacoLivre(const APasta: string): Int64;
var
  Livre, Total, TotalLivre: Int64;
begin
  if FEspacoLivreFixo >= 0 then
    Exit(FEspacoLivreFixo);
  if GetDiskFreeSpaceEx(PChar(IncludeTrailingPathDelimiter(APasta)), Livre, Total, @TotalLivre) then
    Result := Livre
  else
    Result := 0;
end;

function TBackup.CopiarArquivo(const AOrigem, ADestino: string; out AErro: string): Boolean;
begin
  AErro := '';
  Result := CopyFile(PChar(AOrigem), PChar(ADestino), False);
  if not Result then
    AErro := SysErrorMessage(GetLastError);
end;

function TBackup.ExecutarBanco(const ABanco: TBancoConfig): TResultadoBanco;
var
  Quando: TDateTime;
  Fbk, Fdb, Ultima, Erro: string;
  Codigo: Integer;
  Necessario: Int64;
  Erros: TStringList;

  procedure Falha(const AMsg: string);
  begin
    Erros.Add(AMsg);
    FLog.Escrever('ERRO ' + ABanco.Nome + ': ' + AMsg);
  end;

begin
  Quando := Momento;
  Result := Default(TResultadoBanco);
  Result.Nome := ABanco.Nome;
  Result.Inicio := Quando;
  Erros := TStringList.Create;
  try
    FLog.Escrever('=== Banco ' + ABanco.Nome + ' (' + ABanco.Arquivo + ')');
    // 1. Recuperação de lock pendente
    if TFile.Exists(MarcadorLock(ABanco.Nome)) then
    begin
      FLog.Escrever('Marcador de lock pendente encontrado; destravando antes de continuar');
      Codigo := Rodar(FConfig.Nbackup, '-N ' + Aspas(ABanco.Arquivo), Ultima);
      if Codigo <> 0 then
        FLog.Escrever('Aviso: nbackup -N retornou ' + IntToStr(Codigo) + ' (' + Ultima + '); seguindo');
      TFile.Delete(MarcadorLock(ABanco.Nome));
    end;
    // 2. Espaço livre
    Necessario := 0;
    if FConfig.CopiaFbk then
      Inc(Necessario, TFile.GetSize(ABanco.Arquivo));
    if FConfig.CopiaFdb then
      Inc(Necessario, TFile.GetSize(ABanco.Arquivo));
    if EspacoLivre(FConfig.Destino) < Necessario then
    begin
      Falha(Format('Espaço insuficiente em %s: necessário %d bytes', [FConfig.Destino, Necessario]));
      Exit;
    end;
    // 3. gbak
    if FConfig.CopiaFbk then
    begin
      Fbk := NomeArquivoBackup(FConfig.Destino, ABanco.Nome, Quando, '.fbk');
      Codigo := Rodar(FConfig.Gbak, '-b -g -v -se localhost:service_mgr ' + Aspas(ABanco.Arquivo)
        + ' ' + Aspas(Fbk), Ultima);
      if Codigo <> 0 then
        Falha('gbak retornou ' + IntToStr(Codigo) + ': ' + Ultima)
      else if TFile.Exists(Fbk) then
        Result.TamanhoFbk := TFile.GetSize(Fbk);
    end;
    // 4. nbackup
    if FConfig.CopiaFdb then
    begin
      Fdb := NomeArquivoBackup(FConfig.Destino, ABanco.Nome, Quando, '.fdb');
      Codigo := Rodar(FConfig.Nbackup, '-L ' + Aspas(ABanco.Arquivo), Ultima);
      if Codigo <> 0 then
        Falha('nbackup -L retornou ' + IntToStr(Codigo) + ': ' + Ultima)
      else
      begin
        TFile.WriteAllText(MarcadorLock(ABanco.Nome), FormatDateTime('yyyy-mm-dd hh:nn:ss', Quando));
        try
          FLog.Escrever('Copiando ' + ABanco.Arquivo + ' -> ' + Fdb);
          if not CopiarArquivo(ABanco.Arquivo, Fdb, Erro) then
            Falha('cópia do arquivo falhou: ' + Erro);
        finally
          Codigo := Rodar(FConfig.Nbackup, '-N ' + Aspas(ABanco.Arquivo), Ultima);
          if Codigo <> 0 then
            Falha('nbackup -N retornou ' + IntToStr(Codigo) + ': ' + Ultima)
          else
            TFile.Delete(MarcadorLock(ABanco.Nome));
        end;
        if TFile.Exists(Fdb) and (Erro = '') then
        begin
          Codigo := Rodar(FConfig.Nbackup, '-F ' + Aspas(Fdb), Ultima);
          if Codigo <> 0 then
            Falha('nbackup -F retornou ' + IntToStr(Codigo) + ': ' + Ultima)
          else
            Result.TamanhoFdb := TFile.GetSize(Fdb);
        end;
      end;
    end;
  finally
    Result.Fim := Momento;
    Result.OK := Erros.Count = 0;
    Result.Mensagem := Erros.Text.Trim;
    if Result.OK then
      FLog.Escrever('Banco ' + ABanco.Nome + ': OK')
    else
      FLog.Escrever('Banco ' + ABanco.Nome + ': ERRO');
    Erros.Free;
  end;
end;

function TBackup.Executar: Boolean;
var
  Resultados: TArray<TResultadoBanco>;
  I: Integer;
begin
  Result := True;
  FLog.Escrever('Início do backup');
  SetLength(Resultados, FConfig.Bancos.Count);
  for I := 0 to FConfig.Bancos.Count - 1 do
  begin
    Resultados[I] := ExecutarBanco(FConfig.Bancos[I]);
    Result := Result and Resultados[I].OK;
  end;
  AplicarRetencao;
  GravarStatus(Resultados);
  FLog.Escrever('Fim do backup: ' + IfThen(Result, 'OK', 'ERRO'));
end;
```

Observações para quem implementa:
- `Momento` quando `FAgora = 0` chama `Now` a cada uso; `Result.Fim` muda de verdade. Nos testes `FAgora` fixo faz `Fim = Inicio`, o que é esperado.
- `TestLockPendenteOrfaoNaoAborta` espera 3 chamadas: `-N` (recuperação, falha e vira aviso), `-L`, `-N` (normal, falha). O `-F` só roda se o `-N` normal retornou 0: guardar `CodigoN` e usar `if TFile.Exists(Fdb) and (Erro = '') and (CodigoN = 0)`. Quando o `-N` falha, o marcador `.lock-pendente` **fica** no disco (a recuperação tenta de novo na próxima execução).
- `Winapi.Windows` entra no `uses` da implementation (`CopyFile`, `GetDiskFreeSpaceEx`).

- [ ] **Step 4: Rodar `testar.cmd`** — Expected: `Tests Passed : 35`, exit 0.

---

### Task 7: `pAgenda` — decisão do timer e comando do Agendador

**Files:**
- Create: `src/pAgenda.pas`, `tests/pTesteAgenda.pas`
- Modify: `tests/Testes.dpr`

**Interfaces:**
- Produces:
  ```pascal
  function DeveDisparar(AAgora: TDateTime; const AHorario: string; AUltimaExecucao: TDateTime): Boolean;
    // True quando AAgora >= (hoje + AHorario) e Trunc(AUltimaExecucao) < Trunc(AAgora)
  function ArgumentosSchtasks(const AExe, AHorario: string): string;
    // /Create /F /SC DAILY /TN FirebirdBackup /TR "\"<exe>\" --run" /ST HH:MM /RU SYSTEM /RL HIGHEST
  function AgendarTarefa(const AExe, AHorario: string; out ASaida: string): Boolean;
    // roda schtasks via ExecutarProcesso; True se exit 0; ASaida = linhas concatenadas
  ```
  Desvio da spec registrado: o timer não exige igualdade de `HH:MM`; dispara na primeira verificação em que o horário já passou e ainda não houve execução hoje (cobre app aberto atrasado e evita perder o minuto por deriva do timer). `UltimaExecucao` vem de `TBackup.LerUltimaExecucao`, compartilhado com o modo `--run`.

- [ ] **Step 1: Escrever `tests/pTesteAgenda.pas`**

```pascal
unit pTesteAgenda;

interface

uses
  DUnitX.TestFramework, System.SysUtils, pAgenda;

type
  [TestFixture]
  TTesteAgenda = class
  public
    [Test] procedure TestNaoDisparaAntesDoHorario;
    [Test] procedure TestDisparaNoHorario;
    [Test] procedure TestDisparaAtrasadoUmaVez;
    [Test] procedure TestNaoDisparaSeJaRodouHoje;
    [Test] procedure TestDisparaSeUltimaFoiOntem;
    [Test] procedure TestComandoSchtasks;
  end;

implementation

procedure TTesteAgenda.TestNaoDisparaAntesDoHorario;
begin
  Assert.IsFalse(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(1, 59, 0, 0), '02:00', 0));
end;

procedure TTesteAgenda.TestDisparaNoHorario;
begin
  Assert.IsTrue(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0), '02:00', 0));
end;

procedure TTesteAgenda.TestDisparaAtrasadoUmaVez;
begin
  Assert.IsTrue(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(10, 0, 0, 0), '02:00',
    EncodeDate(2026, 10, 4) + EncodeTime(2, 0, 0, 0)));
end;

procedure TTesteAgenda.TestNaoDisparaSeJaRodouHoje;
begin
  Assert.IsFalse(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(10, 0, 0, 0), '02:00',
    EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 30, 0)));
end;

procedure TTesteAgenda.TestDisparaSeUltimaFoiOntem;
begin
  Assert.IsTrue(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(2, 1, 0, 0), '02:00',
    EncodeDate(2026, 10, 4) + EncodeTime(23, 59, 0, 0)));
end;

procedure TTesteAgenda.TestComandoSchtasks;
begin
  Assert.AreEqual(
    '/Create /F /SC DAILY /TN FirebirdBackup /TR "\"C:\Program Files\Bk\FirebirdBackup.exe\" --run" /ST 02:00 /RU SYSTEM /RL HIGHEST',
    ArgumentosSchtasks('C:\Program Files\Bk\FirebirdBackup.exe', '02:00'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteAgenda);

end.
```

- [ ] **Step 2: Adicionar ao `Testes.dpr`; rodar** — Expected: falha de compilação.

- [ ] **Step 3: Implementar `src/pAgenda.pas`**

```pascal
unit pAgenda;

interface

function DeveDisparar(AAgora: TDateTime; const AHorario: string; AUltimaExecucao: TDateTime): Boolean;
function ArgumentosSchtasks(const AExe, AHorario: string): string;
function AgendarTarefa(const AExe, AHorario: string; out ASaida: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, pProcesso;

function DeveDisparar(AAgora: TDateTime; const AHorario: string; AUltimaExecucao: TDateTime): Boolean;
var
  H, M: Integer;
  Alvo: TDateTime;
begin
  H := StrToIntDef(Copy(AHorario, 1, 2), -1);
  M := StrToIntDef(Copy(AHorario, 4, 2), -1);
  if (H < 0) or (M < 0) then
    Exit(False);
  Alvo := Trunc(AAgora) + EncodeTime(H, M, 0, 0);
  Result := (AAgora >= Alvo) and (Trunc(AUltimaExecucao) < Trunc(AAgora));
end;

function ArgumentosSchtasks(const AExe, AHorario: string): string;
begin
  Result := '/Create /F /SC DAILY /TN FirebirdBackup /TR "\"' + AExe + '\" --run" /ST ' + AHorario
    + ' /RU SYSTEM /RL HIGHEST';
end;

function AgendarTarefa(const AExe, AHorario: string; out ASaida: string): Boolean;
var
  Linhas: TStringList;
  Schtasks: string;
begin
  Linhas := TStringList.Create;
  try
    Schtasks := IncludeTrailingPathDelimiter(GetEnvironmentVariable('SystemRoot')) + 'System32\schtasks.exe';
    Result := ExecutarProcesso(Schtasks, ArgumentosSchtasks(AExe, AHorario), nil,
      procedure(const L: string) begin Linhas.Add(L); end) = 0;
    ASaida := Linhas.Text.Trim;
  finally
    Linhas.Free;
  end;
end;

end.
```

Nota: a exe é 32 bits; em Windows 64 o `System32` é redirecionado para `SysWOW64`, que também tem `schtasks.exe`. Funciona.

- [ ] **Step 4: Rodar `testar.cmd`** — Expected: `Tests Passed : 41`, exit 0.

---

### Task 8: `.dpr` com modo `--run`, instância única e teste de integração com Firebird real

**Files:**
- Modify: `FirebirdBackup.dpr`
- Create: `src/pPrincipal.pas` (apenas um form vazio nesta task; a tela completa é a Task 9), `src/pPrincipal.dfm`

**Interfaces:**
- Consumes: `TConfig`, `TLog`, `TBackup`.
- Produces: `FirebirdBackup.exe --run` (exit 0/1/2) e `FirebirdBackup.exe` (abre `TFormPrincipal`).

- [ ] **Step 1: Form vazio `src/pPrincipal.pas` + `.dfm`**

```pascal
unit pPrincipal;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, Vcl.Forms, Vcl.Controls;

type
  TFormPrincipal = class(TForm)
  end;

var
  FormPrincipal: TFormPrincipal;

implementation

{$R *.dfm}

end.
```

```
object FormPrincipal: TFormPrincipal
  Left = 0
  Top = 0
  Caption = 'Backup Firebird'
  ClientHeight = 560
  ClientWidth = 760
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  PixelsPerInch = 96
  TextHeight = 15
end
```

- [ ] **Step 2: `FirebirdBackup.dpr` completo**

```pascal
program FirebirdBackup;

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  pConfig in 'src\pConfig.pas',
  pLog in 'src\pLog.pas',
  pProcesso in 'src\pProcesso.pas',
  pBackup in 'src\pBackup.pas',
  pAgenda in 'src\pAgenda.pas',
  pPrincipal in 'src\pPrincipal.pas' {FormPrincipal};

function ModoRun: Integer;
var
  Config: TConfig;
  Log: TLog;
  Backup: TBackup;
  Erro: string;
begin
  Config := TConfig.Create;
  try
    Config.Carregar(TConfig.ArquivoPadrao);
    if not Config.Validar(Erro) then
    begin
      // Sem destino válido não há onde logar: grava ao lado da exe
      Log := TLog.Create(ExtractFilePath(ParamStr(0)));
      try
        Log.Escrever('Configuração inválida: ' + Erro);
      finally
        Log.Free;
      end;
      Exit(2);
    end;
    Log := TLog.Create(Config.Destino);
    try
      Backup := TBackup.Create(Config, Log);
      try
        if Backup.Executar then
          Result := 0
        else
          Result := 1;
      finally
        Backup.Free;
      end;
    finally
      Log.Free;
    end;
  finally
    Config.Free;
  end;
end;

const
  NomeMutex = 'FirebirdBackup_Instancia_Unica';

var
  Mutex: THandle;
  Janela: HWND;

begin
  if FindCmdLineSwitch('run', ['-', '/'], True) then
  begin
    ExitCode := ModoRun;
    Exit;
  end;
  Mutex := CreateMutex(nil, True, NomeMutex);
  if (Mutex = 0) or (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    Janela := FindWindow('TFormPrincipal', nil);
    if Janela <> 0 then
    begin
      ShowWindow(Janela, SW_RESTORE);
      SetForegroundWindow(Janela);
    end;
    Exit;
  end;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Backup Firebird';
  Application.CreateForm(TFormPrincipal, FormPrincipal);
  Application.Run;
  ReleaseMutex(Mutex);
  CloseHandle(Mutex);
end.
```

`FindCmdLineSwitch('run', ['-', '/'], True)` aceita `--run`? Não: ele tira **um** prefixo. Usar `FindCmdLineSwitch('-run', ['-', '/'], True)` para casar `--run`, e aceitar também `-run` e `/run` com uma segunda chamada: `if FindCmdLineSwitch('-run', ['-','/'], True) or FindCmdLineSwitch('run', ['-','/'], True) then`.

- [ ] **Step 3: `build.cmd`; conferir que compila**

Run: `cmd /c C:\Sistemas\Bulls\FirebirdBackup\build.cmd` — Expected: exit 0, `bin\FirebirdBackup.exe` gerado.

- [ ] **Step 4: Teste de integração manual com Firebird 3.0 local** (o comportamento de `gbak`/`nbackup` é o mesmo no 2.5)

Pré-requisito: senha do SYSDBA local em `ISC_PASSWORD` na sessão (não gravar em arquivo do repo).

1. Criar banco de teste (em `C:\Users\Maikon\AppData\Local\Temp\claude\...\scratchpad\fbtest\TESTE.FDB`) com `isql -q -i cria.sql` (script `CREATE DATABASE 'localhost:<caminho>' USER 'SYSDBA' PASSWORD '<senha>'; CREATE TABLE T (ID INTEGER); INSERT INTO T VALUES (1); COMMIT;`).
2. Criar `bin\backup.ini`:
   ```ini
   [Geral]
   FirebirdDir=C:\Program Files (x86)\Firebird\Firebird_3_0
   Usuario=SYSDBA
   Senha=<senha>
   Destino=<scratchpad>\fbtest\dest
   RetencaoDias=7
   Horario=02:00
   CopiaFbk=1
   CopiaFdb=1
   [Banco1]
   Nome=TESTE
   Arquivo=<scratchpad>\fbtest\TESTE.FDB
   ```
3. Run: `bin\FirebirdBackup.exe --run`; `echo %ERRORLEVEL%` — Expected: `0`; em `dest` existem `TESTE_<data>.fbk`, `TESTE_<data>.fdb`, `backup_<dia>.log`, `ultimo-status.ini`; o log contém as linhas `gbak:` do `-v`.
4. Conferir a cópia física: `isql -user SYSDBA -password <senha> "localhost:<dest>\TESTE_<data>.fdb"` com `SELECT * FROM T;` — Expected: 1 linha com `1`.
5. Conferir o `.fbk`: `gbak -c -se localhost:service_mgr <dest>\TESTE_<data>.fbk <scratchpad>\fbtest\RESTAURADO.FDB` — Expected: exit 0.
6. Simular lock pendente: `nbackup -L TESTE.FDB` manual + criar `dest\TESTE.lock-pendente`; rodar `--run` de novo — Expected: log mostra o `-N` de recuperação antes do `-L`, exit 0, banco destravado (`nbackup -L` seguido de `-N` manual funciona).
7. Apagar `bin\backup.ini` ao final (contém a senha). Remover `backup.ini` e `*.ini` da pasta `bin` do controle de versão (já no `.gitignore`).

Registrar no plan o resultado de cada item (feito/falhou/não rodou).

---

### Task 9: Tela `pPrincipal` — configuração, executar agora, tray, timer, agendar

**Files:**
- Modify: `src/pPrincipal.pas`, `src/pPrincipal.dfm`

**Interfaces:**
- Consumes: `TConfig` (Carregar/Salvar/Validar/ArquivoPadrao), `TLog.OnLinha`, `TBackup.Executar`, `TBackup.LerUltimaExecucao`, `DeveDisparar`, `AgendarTarefa`.

- [ ] **Step 1: `.dfm` completo**

```
object FormPrincipal: TFormPrincipal
  Left = 0
  Top = 0
  Caption = 'Backup Firebird'
  ClientHeight = 600
  ClientWidth = 780
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object gbFirebird: TGroupBox
    Left = 8
    Top = 8
    Width = 380
    Height = 120
    Caption = ' Firebird '
    TabOrder = 0
    object lblFirebirdDir: TLabel
      Left = 12
      Top = 24
      Width = 100
      Height = 15
      Caption = 'Pasta do Firebird:'
    end
    object lblUsuario: TLabel
      Left = 12
      Top = 84
      Width = 44
      Height = 15
      Caption = 'Usu'#225'rio:'
    end
    object lblSenha: TLabel
      Left = 196
      Top = 84
      Width = 37
      Height = 15
      Caption = 'Senha:'
    end
    object edtFirebirdDir: TEdit
      Left = 12
      Top = 44
      Width = 320
      Height = 23
      TabOrder = 0
    end
    object btnFirebirdDir: TButton
      Left = 336
      Top = 43
      Width = 32
      Height = 25
      Caption = '...'
      TabOrder = 1
      OnClick = btnFirebirdDirClick
    end
    object edtUsuario: TEdit
      Left = 68
      Top = 80
      Width = 116
      Height = 23
      TabOrder = 2
    end
    object edtSenha: TEdit
      Left = 240
      Top = 80
      Width = 128
      Height = 23
      PasswordChar = '*'
      TabOrder = 3
    end
  end
  object gbDestino: TGroupBox
    Left = 396
    Top = 8
    Width = 376
    Height = 120
    Caption = ' Destino e rotina '
    TabOrder = 1
    object lblDestino: TLabel
      Left = 12
      Top = 24
      Width = 86
      Height = 15
      Caption = 'Pasta de destino:'
    end
    object lblRetencao: TLabel
      Left = 12
      Top = 84
      Width = 90
      Height = 15
      Caption = 'Manter por (dias):'
    end
    object lblHorario: TLabel
      Left = 164
      Top = 84
      Width = 44
      Height = 15
      Caption = 'Hor'#225'rio:'
    end
    object edtDestino: TEdit
      Left = 12
      Top = 44
      Width = 316
      Height = 23
      TabOrder = 0
    end
    object btnDestino: TButton
      Left = 332
      Top = 43
      Width = 32
      Height = 25
      Caption = '...'
      TabOrder = 1
      OnClick = btnDestinoClick
    end
    object edtRetencao: TEdit
      Left = 108
      Top = 80
      Width = 40
      Height = 23
      NumbersOnly = True
      TabOrder = 2
      Text = '7'
    end
    object edtHorario: TMaskEdit
      Left = 214
      Top = 80
      Width = 50
      Height = 23
      EditMask = '!90:00;1;_'
      MaxLength = 5
      TabOrder = 3
      Text = '02:00'
    end
    object chkFbk: TCheckBox
      Left = 276
      Top = 70
      Width = 90
      Height = 17
      Caption = 'C'#243'pia .fbk'
      Checked = True
      State = cbChecked
      TabOrder = 4
    end
    object chkFdb: TCheckBox
      Left = 276
      Top = 92
      Width = 90
      Height = 17
      Caption = 'C'#243'pia .fdb'
      Checked = True
      State = cbChecked
      TabOrder = 5
    end
  end
  object gbBancos: TGroupBox
    Left = 8
    Top = 136
    Width = 764
    Height = 150
    Caption = ' Bancos '
    TabOrder = 2
    object lvBancos: TListView
      Left = 12
      Top = 24
      Width = 640
      Height = 112
      Columns = <
        item
          Caption = 'Nome'
          Width = 140
        end
        item
          Caption = 'Arquivo'
          Width = 480
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
    end
    object btnAdicionar: TButton
      Left = 660
      Top = 24
      Width = 92
      Height = 25
      Caption = 'Adicionar...'
      TabOrder = 1
      OnClick = btnAdicionarClick
    end
    object btnEditar: TButton
      Left = 660
      Top = 55
      Width = 92
      Height = 25
      Caption = 'Editar...'
      TabOrder = 2
      OnClick = btnEditarClick
    end
    object btnRemover: TButton
      Left = 660
      Top = 86
      Width = 92
      Height = 25
      Caption = 'Remover'
      TabOrder = 3
      OnClick = btnRemoverClick
    end
  end
  object pnlBotoes: TPanel
    Left = 8
    Top = 294
    Width = 764
    Height = 40
    BevelOuter = bvNone
    TabOrder = 3
    object btnSalvar: TButton
      Left = 0
      Top = 6
      Width = 110
      Height = 28
      Caption = 'Salvar'
      TabOrder = 0
      OnClick = btnSalvarClick
    end
    object btnAgendar: TButton
      Left = 116
      Top = 6
      Width = 150
      Height = 28
      Caption = 'Agendar no Windows'
      TabOrder = 1
      OnClick = btnAgendarClick
    end
    object btnExecutar: TButton
      Left = 272
      Top = 6
      Width = 130
      Height = 28
      Caption = 'Executar agora'
      TabOrder = 2
      OnClick = btnExecutarClick
    end
    object pbAndamento: TProgressBar
      Left = 412
      Top = 10
      Width = 340
      Height = 20
      Style = pbstMarquee
      TabOrder = 3
      Visible = False
    end
  end
  object gbUltimo: TGroupBox
    Left = 8
    Top = 340
    Width = 764
    Height = 92
    Caption = ' '#218'ltimo backup '
    TabOrder = 4
    object lvUltimo: TListView
      Left = 12
      Top = 22
      Width = 740
      Height = 60
      Columns = <
        item
          Caption = 'Banco'
          Width = 110
        end
        item
          Caption = 'In'#237'cio'
          Width = 130
        end
        item
          Caption = 'Dura'#231#227'o'
          Width = 70
        end
        item
          Caption = 'Resultado'
          Width = 70
        end
        item
          Caption = '.fbk (MB)'
          Width = 70
        end
        item
          Caption = '.fdb (MB)'
          Width = 70
        end
        item
          Caption = 'Mensagem'
          Width = 200
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
    end
  end
  object memoLog: TMemo
    Left = 8
    Top = 440
    Width = 764
    Height = 152
    Font.Charset = ANSI_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 5
  end
  object TrayIcon: TTrayIcon
    PopupMenu = pmTray
    Visible = True
    OnDblClick = miAbrirClick
    Left = 712
    Top = 296
  end
  object pmTray: TPopupMenu
    Left = 744
    Top = 296
    object miAbrir: TMenuItem
      Caption = 'Abrir'
      Default = True
      OnClick = miAbrirClick
    end
    object miExecutar: TMenuItem
      Caption = 'Executar agora'
      OnClick = btnExecutarClick
    end
    object miSep: TMenuItem
      Caption = '-'
    end
    object miSair: TMenuItem
      Caption = 'Sair'
      OnClick = miSairClick
    end
  end
  object Timer: TTimer
    Interval = 60000
    OnTimer = TimerTimer
    Left = 680
    Top = 296
  end
end
```

- [ ] **Step 2: `src/pPrincipal.pas` completo**

```pascal
unit pPrincipal;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IniFiles,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Mask,
  Vcl.Dialogs, Vcl.FileCtrl,
  pConfig, pLog, pBackup;

type
  TFormPrincipal = class(TForm)
    gbFirebird: TGroupBox;
    lblFirebirdDir: TLabel;
    lblUsuario: TLabel;
    lblSenha: TLabel;
    edtFirebirdDir: TEdit;
    btnFirebirdDir: TButton;
    edtUsuario: TEdit;
    edtSenha: TEdit;
    gbDestino: TGroupBox;
    lblDestino: TLabel;
    lblRetencao: TLabel;
    lblHorario: TLabel;
    edtDestino: TEdit;
    btnDestino: TButton;
    edtRetencao: TEdit;
    edtHorario: TMaskEdit;
    chkFbk: TCheckBox;
    chkFdb: TCheckBox;
    gbBancos: TGroupBox;
    lvBancos: TListView;
    btnAdicionar: TButton;
    btnEditar: TButton;
    btnRemover: TButton;
    pnlBotoes: TPanel;
    btnSalvar: TButton;
    btnAgendar: TButton;
    btnExecutar: TButton;
    pbAndamento: TProgressBar;
    gbUltimo: TGroupBox;
    lvUltimo: TListView;
    memoLog: TMemo;
    TrayIcon: TTrayIcon;
    pmTray: TPopupMenu;
    miAbrir: TMenuItem;
    miExecutar: TMenuItem;
    miSep: TMenuItem;
    miSair: TMenuItem;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnFirebirdDirClick(Sender: TObject);
    procedure btnDestinoClick(Sender: TObject);
    procedure btnAdicionarClick(Sender: TObject);
    procedure btnEditarClick(Sender: TObject);
    procedure btnRemoverClick(Sender: TObject);
    procedure btnSalvarClick(Sender: TObject);
    procedure btnAgendarClick(Sender: TObject);
    procedure btnExecutarClick(Sender: TObject);
    procedure miAbrirClick(Sender: TObject);
    procedure miSairClick(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
  private
    FConfig: TConfig;
    FExecutando: Boolean;
    FSair: Boolean;
    procedure ConfigParaTela;
    function TelaParaConfig(out AErro: string): Boolean;
    procedure PreencherBancos;
    procedure CarregarUltimoStatus;
    function EditarBanco(var ABanco: TBancoConfig): Boolean;
    procedure IniciarBackup(const AOrigem: string);
    procedure AoTerminar(AOk: Boolean);
    procedure Habilitar(AAtivo: Boolean);
  end;

var
  FormPrincipal: TFormPrincipal;

implementation

uses
  System.IOUtils, pAgenda;

{$R *.dfm}

procedure TFormPrincipal.FormCreate(Sender: TObject);
begin
  FConfig := TConfig.Create;
  if TFile.Exists(TConfig.ArquivoPadrao) then
    FConfig.Carregar(TConfig.ArquivoPadrao);
  ConfigParaTela;
  CarregarUltimoStatus;
  TrayIcon.Hint := Application.Title;
  TrayIcon.Icon := Application.Icon;
end;

procedure TFormPrincipal.FormDestroy(Sender: TObject);
begin
  FConfig.Free;
end;

procedure TFormPrincipal.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FSair then
  begin
    CanClose := not FExecutando or
      (MessageDlg('Há um backup em andamento. Sair mesmo assim?', mtWarning, [mbYes, mbNo], 0) = mrYes);
    Exit;
  end;
  CanClose := False;
  Hide;
  TrayIcon.BalloonTitle := Application.Title;
  TrayIcon.BalloonHint := 'Continua rodando aqui. Clique duas vezes para abrir.';
  TrayIcon.ShowBalloonHint;
end;

procedure TFormPrincipal.ConfigParaTela;
begin
  edtFirebirdDir.Text := FConfig.FirebirdDir;
  edtUsuario.Text := FConfig.Usuario;
  edtSenha.Text := FConfig.Senha;
  edtDestino.Text := FConfig.Destino;
  edtRetencao.Text := IntToStr(FConfig.RetencaoDias);
  edtHorario.Text := FConfig.Horario;
  chkFbk.Checked := FConfig.CopiaFbk;
  chkFdb.Checked := FConfig.CopiaFdb;
  PreencherBancos;
end;

function TFormPrincipal.TelaParaConfig(out AErro: string): Boolean;
begin
  FConfig.FirebirdDir := Trim(edtFirebirdDir.Text);
  FConfig.Usuario := Trim(edtUsuario.Text);
  FConfig.Senha := edtSenha.Text;
  FConfig.Destino := Trim(edtDestino.Text);
  FConfig.RetencaoDias := StrToIntDef(edtRetencao.Text, 0);
  FConfig.Horario := Trim(edtHorario.Text);
  FConfig.CopiaFbk := chkFbk.Checked;
  FConfig.CopiaFdb := chkFdb.Checked;
  Result := FConfig.Validar(AErro);
end;

procedure TFormPrincipal.PreencherBancos;
var
  B: TBancoConfig;
  Item: TListItem;
begin
  lvBancos.Items.BeginUpdate;
  try
    lvBancos.Items.Clear;
    for B in FConfig.Bancos do
    begin
      Item := lvBancos.Items.Add;
      Item.Caption := B.Nome;
      Item.SubItems.Add(B.Arquivo);
    end;
  finally
    lvBancos.Items.EndUpdate;
  end;
end;

procedure TFormPrincipal.CarregarUltimoStatus;
var
  Ini: TIniFile;
  B: TBancoConfig;
  Item: TListItem;
  Arq: string;
  function MB(const S: string): string;
  begin
    Result := FormatFloat('0.0', StrToInt64Def(S, 0) / 1048576);
  end;
begin
  lvUltimo.Items.Clear;
  Arq := TPath.Combine(FConfig.Destino, 'ultimo-status.ini');
  if (FConfig.Destino = '') or not TFile.Exists(Arq) then
    Exit;
  Ini := TIniFile.Create(Arq);
  try
    for B in FConfig.Bancos do
      if Ini.SectionExists(B.Nome) then
      begin
        Item := lvUltimo.Items.Add;
        Item.Caption := B.Nome;
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'Inicio', ''));
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'DuracaoSeg', '') + ' s');
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'Resultado', ''));
        Item.SubItems.Add(MB(Ini.ReadString(B.Nome, 'TamanhoFbk', '0')));
        Item.SubItems.Add(MB(Ini.ReadString(B.Nome, 'TamanhoFdb', '0')));
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'Mensagem', ''));
      end;
  finally
    Ini.Free;
  end;
end;

procedure TFormPrincipal.btnFirebirdDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := edtFirebirdDir.Text;
  if SelectDirectory('Pasta do Firebird (onde estão gbak.exe e nbackup.exe)', '', Dir,
    [sdNewUI], Self) then
    edtFirebirdDir.Text := Dir;
end;

procedure TFormPrincipal.btnDestinoClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := edtDestino.Text;
  if SelectDirectory('Pasta de destino dos backups', '', Dir, [sdNewUI, sdNewFolder], Self) then
    edtDestino.Text := Dir;
end;

function TFormPrincipal.EditarBanco(var ABanco: TBancoConfig): Boolean;
var
  Nome: string;
  Dlg: TOpenDialog;
begin
  Result := False;
  Nome := ABanco.Nome;
  if not InputQuery('Banco', 'Nome (só letras, dígitos, - e _):', Nome) then
    Exit;
  if not TConfig.NomeValido(Trim(Nome)) then
  begin
    MessageDlg('Nome inválido.', mtError, [mbOK], 0);
    Exit;
  end;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Arquivo do banco (.FDB)';
    Dlg.Filter := 'Banco Firebird (*.fdb;*.gdb)|*.fdb;*.gdb|Todos (*.*)|*.*';
    Dlg.FileName := ABanco.Arquivo;
    Dlg.Options := [ofFileMustExist, ofHideReadOnly];
    if not Dlg.Execute(Handle) then
      Exit;
    ABanco.Nome := Trim(Nome);
    ABanco.Arquivo := Dlg.FileName;
    Result := True;
  finally
    Dlg.Free;
  end;
end;

procedure TFormPrincipal.btnAdicionarClick(Sender: TObject);
var
  B: TBancoConfig;
begin
  B := Default(TBancoConfig);
  if EditarBanco(B) then
  begin
    FConfig.Bancos.Add(B);
    PreencherBancos;
  end;
end;

procedure TFormPrincipal.btnEditarClick(Sender: TObject);
var
  B: TBancoConfig;
  I: Integer;
begin
  if lvBancos.ItemIndex < 0 then
    Exit;
  I := lvBancos.ItemIndex;
  B := FConfig.Bancos[I];
  if EditarBanco(B) then
  begin
    FConfig.Bancos[I] := B;
    PreencherBancos;
  end;
end;

procedure TFormPrincipal.btnRemoverClick(Sender: TObject);
begin
  if lvBancos.ItemIndex < 0 then
    Exit;
  FConfig.Bancos.Delete(lvBancos.ItemIndex);
  PreencherBancos;
end;

procedure TFormPrincipal.btnSalvarClick(Sender: TObject);
var
  Erro: string;
begin
  if not TelaParaConfig(Erro) then
  begin
    MessageDlg(Erro, mtError, [mbOK], 0);
    Exit;
  end;
  FConfig.Salvar(TConfig.ArquivoPadrao);
  CarregarUltimoStatus;
  MessageDlg('Configuração salva.', mtInformation, [mbOK], 0);
end;

procedure TFormPrincipal.btnAgendarClick(Sender: TObject);
var
  Erro, Saida: string;
begin
  if not TelaParaConfig(Erro) then
  begin
    MessageDlg(Erro, mtError, [mbOK], 0);
    Exit;
  end;
  FConfig.Salvar(TConfig.ArquivoPadrao);
  if AgendarTarefa(ParamStr(0), FConfig.Horario, Saida) then
    MessageDlg('Tarefa "FirebirdBackup" agendada todo dia às ' + FConfig.Horario + '.' + sLineBreak + Saida,
      mtInformation, [mbOK], 0)
  else
    MessageDlg('Não foi possível agendar (execute como administrador).' + sLineBreak + Saida,
      mtError, [mbOK], 0);
end;

procedure TFormPrincipal.Habilitar(AAtivo: Boolean);
begin
  btnSalvar.Enabled := AAtivo;
  btnAgendar.Enabled := AAtivo;
  btnExecutar.Enabled := AAtivo;
  miExecutar.Enabled := AAtivo;
  btnAdicionar.Enabled := AAtivo;
  btnEditar.Enabled := AAtivo;
  btnRemover.Enabled := AAtivo;
  pbAndamento.Visible := not AAtivo;
end;

procedure TFormPrincipal.IniciarBackup(const AOrigem: string);
var
  Erro: string;
  Config: TConfig;
  B: TBancoConfig;
begin
  if FExecutando then
    Exit;
  if not TelaParaConfig(Erro) then
  begin
    memoLog.Lines.Add('Configuração inválida: ' + Erro);
    if AOrigem <> 'timer' then
      MessageDlg(Erro, mtError, [mbOK], 0);
    Exit;
  end;
  FConfig.Salvar(TConfig.ArquivoPadrao);
  // cópia da config para a thread não disputar com a tela
  Config := TConfig.Create;
  Config.FirebirdDir := FConfig.FirebirdDir; Config.Usuario := FConfig.Usuario;
  Config.Senha := FConfig.Senha; Config.Destino := FConfig.Destino;
  Config.RetencaoDias := FConfig.RetencaoDias; Config.Horario := FConfig.Horario;
  Config.CopiaFbk := FConfig.CopiaFbk; Config.CopiaFdb := FConfig.CopiaFdb;
  for B in FConfig.Bancos do
    Config.Bancos.Add(B);
  FExecutando := True;
  Habilitar(False);
  memoLog.Lines.Add('--- Backup iniciado (' + AOrigem + ')');
  TThread.CreateAnonymousThread(
    procedure
    var
      Log: TLog;
      Backup: TBackup;
      Ok: Boolean;
    begin
      Ok := False;
      try
        Log := TLog.Create(Config.Destino);
        try
          Log.OnLinha := procedure(const L: string)
            begin
              TThread.Queue(nil, procedure begin memoLog.Lines.Add(L); end);
            end;
          Backup := TBackup.Create(Config, Log);
          try
            Ok := Backup.Executar;
          finally
            Backup.Free;
          end;
        finally
          Log.Free;
        end;
      finally
        Config.Free;
        TThread.Queue(nil, procedure begin AoTerminar(Ok); end);
      end;
    end).Start;
end;

procedure TFormPrincipal.AoTerminar(AOk: Boolean);
begin
  FExecutando := False;
  Habilitar(True);
  CarregarUltimoStatus;
  if not AOk then
  begin
    TrayIcon.BalloonTitle := 'Backup Firebird';
    TrayIcon.BalloonHint := 'O backup terminou com ERRO. Veja o log.';
    TrayIcon.BalloonFlags := bfError;
    TrayIcon.ShowBalloonHint;
  end;
end;

procedure TFormPrincipal.btnExecutarClick(Sender: TObject);
begin
  IniciarBackup('manual');
end;

procedure TFormPrincipal.TimerTimer(Sender: TObject);
var
  Erro: string;
begin
  if FExecutando then
    Exit;
  if not TelaParaConfig(Erro) then
    Exit;
  if DeveDisparar(Now, FConfig.Horario, TBackup.LerUltimaExecucao(FConfig.Destino)) then
    IniciarBackup('timer');
end;

procedure TFormPrincipal.miAbrirClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  Application.BringToFront;
end;

procedure TFormPrincipal.miSairClick(Sender: TObject);
begin
  FSair := True;
  Close;
end;

end.
```

Cuidados:
- `TelaParaConfig` no timer chama `Validar`, que cria a pasta de destino se não existir. Aceitável.
- `TThread.Queue(nil, …)` entrega na thread principal; `memoLog` nunca é tocado pela thread.
- Se `memoLog` passar de 5.000 linhas, limpar as primeiras 1.000 em `AoTerminar` (`memoLog.Lines.BeginUpdate` … `Delete(0)`); implementar no mesmo passo.
- `Vcl.FileCtrl.SelectDirectory` com `sdNewUI` abre o diálogo moderno.

- [ ] **Step 3: Ícone**

Gerar `FirebirdBackup.res` com um ícone: criar `recursos/app.rc` com `MAINICON ICON "app.ico"` e um `app.ico` 32×32 simples (pode ser copiado de `%BDS%\bin\delphi_PROJECTICON.ico`); compilar com `brcc32 recursos\app.rc -foFirebirdBackup.res` dentro do `build.cmd` antes do `dcc32`, e restaurar a diretiva `{$R *.res}` no `.dpr`. Sem o ícone o `TrayIcon` usa o da aplicação padrão; não é bloqueante.

- [ ] **Step 4: `build.cmd` e conferência manual da tela**

Run: `cmd /c C:\Sistemas\Bulls\FirebirdBackup\build.cmd` — Expected: exit 0.

Checklist manual (registrar no plan o que foi feito):
1. Abrir `bin\FirebirdBackup.exe` sem `backup.ini`: tela abre com padrões (`7`, `02:00`, ambas cópias marcadas).
2. Preencher com o banco de teste da Task 8, **Salvar**: `bin\backup.ini` gravado com as seções certas; reabrir a exe e ver os campos iguais.
3. **Executar agora**: botões desabilitam, barra marquee aparece, linhas `gbak:` rolam no memo, painel "Último backup" mostra `OK` e tamanhos.
4. Fechar a janela: vai para a bandeja com balão; duplo clique reabre; **Sair** pelo menu encerra.
5. Abrir a exe de novo com uma instância aberta: a janela existente vem para frente, não abre segunda.
6. **Agendar** (sessão administrativa): `schtasks /Query /TN FirebirdBackup` lista a tarefa com `--run`.
7. Timer: ajustar o horário para 1 minuto à frente, salvar, esperar; o backup dispara sozinho uma vez; apagar `ultimo-status.ini` não é necessário para o teste porque a execução anterior foi hoje — para forçar, editar `UltimaExecucao` para ontem.

---

### Task 10: Fechamento — `.dproj`, README curto, status no plan

**Files:**
- Create: `FirebirdBackup.dproj`, `README.md`
- Modify: `docs/plans/2026-10-05-firebird-backup-plan.md` (status final)

- [ ] **Step 1: `FirebirdBackup.dproj` mínimo (Delphi 10.3, Win32)**

```xml
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{7F1C2B6E-3A0D-4C58-9E2B-5D7A1B2C3D4E}</ProjectGuid>
    <ProjectVersion>18.8</ProjectVersion>
    <FrameworkType>VCL</FrameworkType>
    <MainSource>FirebirdBackup.dpr</MainSource>
    <Base>True</Base>
    <Config Condition="'$(Config)'==''">Release</Config>
    <Platform Condition="'$(Platform)'==''">Win32</Platform>
    <TargetedPlatforms>1</TargetedPlatforms>
    <AppType>Application</AppType>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''">
    <Base>true</Base>
  </PropertyGroup>
  <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Base)'=='true') or '$(Base_Win32)'!=''">
    <Base_Win32>true</Base_Win32>
    <CfgParent>Base</CfgParent>
    <Base>true</Base>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Config)'=='Release' or '$(Cfg_1)'!=''">
    <Cfg_1>true</Cfg_1>
    <CfgParent>Base</CfgParent>
    <Base>true</Base>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Config)'=='Debug' or '$(Cfg_2)'!=''">
    <Cfg_2>true</Cfg_2>
    <CfgParent>Base</CfgParent>
    <Base>true</Base>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Base)'!=''">
    <DCC_DcuOutput>dcu</DCC_DcuOutput>
    <DCC_ExeOutput>bin</DCC_ExeOutput>
    <DCC_UnitSearchPath>src;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    <DCC_Namespace>System;Xml;Data;Datasnap;Web;Soap;Vcl;Vcl.Imaging;Winapi;$(DCC_Namespace)</DCC_Namespace>
    <SanitizedProjectName>FirebirdBackup</SanitizedProjectName>
    <VerInfo_Locale>1046</VerInfo_Locale>
    <Icon_MainIcon>recursos\app.ico</Icon_MainIcon>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Base_Win32)'!=''">
    <DCC_UsePackage>vcl;rtl;$(DCC_UsePackage)</DCC_UsePackage>
    <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Cfg_1)'!=''">
    <DCC_DebugInformation>0</DCC_DebugInformation>
    <DCC_Optimize>true</DCC_Optimize>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Cfg_2)'!=''">
    <DCC_Optimize>false</DCC_Optimize>
    <DCC_DebugInformation>2</DCC_DebugInformation>
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="$(MainSource)">
      <MainSource>MainSource</MainSource>
    </DelphiCompile>
    <DCCReference Include="src\pConfig.pas"/>
    <DCCReference Include="src\pLog.pas"/>
    <DCCReference Include="src\pProcesso.pas"/>
    <DCCReference Include="src\pBackup.pas"/>
    <DCCReference Include="src\pAgenda.pas"/>
    <DCCReference Include="src\pPrincipal.pas">
      <Form>FormPrincipal</Form>
    </DCCReference>
    <BuildConfiguration Include="Base">
      <Key>Base</Key>
    </BuildConfiguration>
    <BuildConfiguration Include="Release">
      <Key>Cfg_1</Key>
      <CfgParent>Base</CfgParent>
    </BuildConfiguration>
    <BuildConfiguration Include="Debug">
      <Key>Cfg_2</Key>
      <CfgParent>Base</CfgParent>
    </BuildConfiguration>
  </ItemGroup>
  <ProjectExtensions>
    <Borland.Personality>Delphi.Personality.12</Borland.Personality>
    <Borland.ProjectType>VCLApplication</Borland.ProjectType>
    <BorlandProject>
      <Delphi.Personality>
        <Source>
          <Source Name="MainSource">FirebirdBackup.dpr</Source>
        </Source>
      </Delphi.Personality>
      <Platforms>
        <Platform value="Win32">True</Platform>
      </Platforms>
    </BorlandProject>
    <ProjectFileVersion>12</ProjectFileVersion>
  </ProjectExtensions>
  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists('$(BDS)\Bin\CodeGear.Delphi.Targets')"/>
  <Import Project="$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(BDSVER)\UserTools.proj" Condition="Exists('$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(BDSVER)\UserTools.proj')"/>
</Project>
```

Validar com `msbuild FirebirdBackup.dproj /t:Build /p:Config=Release` dentro de um `cmd` com `rsvars.bat` — Expected: exit 0. Se o msbuild reclamar do `.dproj`, abrir no IDE e deixá-lo regravar o arquivo; registrar.

- [ ] **Step 2: `README.md`** (uso em 10 linhas: copiar `bin\FirebirdBackup.exe` para a pasta no servidor, abrir, configurar, Salvar, Agendar ou deixar aberta; `--run` para o Agendador; onde ficam log e status; `build.cmd`/`testar.cmd` para compilar).

- [ ] **Step 3: Atualizar o cabeçalho de status deste plan**: desvios (timer "atrasado", `-F` condicionado ao `-N`), validações rodadas (contagem de testes, integração Task 8 item a item, checklist Task 9), pendências.
