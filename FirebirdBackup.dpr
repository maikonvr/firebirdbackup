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

{$R *.res}

// Nunca deixa uma exceção escapar: em app GUI sem console ela viraria um MessageBox
// que, na sessão 0 do Agendador (conta SYSTEM), ninguém fecha e a tarefa fica pendurada.
function ModoRun: Integer;
var
  Config: TConfig;
  Log: TLog;
  Backup: TBackup;
  Erro: string;
begin
  try
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
  except
    on E: Exception do
    begin
      try
        Log := TLog.Create(ExtractFilePath(ParamStr(0)));
        try
          Log.Escrever('ERRO fatal: ' + E.ClassName + ': ' + E.Message);
        finally
          Log.Free;
        end;
      except
        // sem onde registrar; o código de saída 1 é o que resta
      end;
      Result := 1;
    end;
  end;
end;

const
  NomeMutex = 'FirebirdBackup_Instancia_Unica';

var
  Mutex: THandle;
  Janela: HWND;

begin
  // aceita --run, -run e /run
  if FindCmdLineSwitch('-run', ['-', '/'], True) or FindCmdLineSwitch('run', ['-', '/'], True) then
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
