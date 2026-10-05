unit pProcesso;

interface

uses
  System.SysUtils, System.Classes, pLog;

const
  // Retornado por ExecutarProcesso quando o processo foi encerrado por tempo limite
  CodigoTimeout = -2;

type
  EProcesso = class(Exception);

  TExecutor = reference to function(const AExe, AArgs: string; AAmbiente: TStrings;
    AOnLinha: TLinhaEvento; ATimeoutMs: Cardinal): Integer;

// Executa AExe com AArgs, janela oculta, prioridade abaixo do normal, stdout+stderr por pipe.
// AAmbiente: lista NOME=VALOR acrescentada ao ambiente atual (pode ser nil).
// ATimeoutMs: 0 = sem limite; senão o processo é encerrado e o retorno é CodigoTimeout.
// AConverterOem: True para ferramentas de console que escrevem em OEM (cmd, schtasks);
//   gbak/nbackup escrevem em ANSI, por isso o padrão é False.
function ExecutarProcesso(const AExe, AArgs: string; AAmbiente: TStrings;
  AOnLinha: TLinhaEvento; ATimeoutMs: Cardinal = 0; AConverterOem: Boolean = False): Integer;
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
    Inicio := GetEnvironmentStrings;
    try
      P := Inicio;
      while P^ <> #0 do
      begin
        Lista.Add(P);
        Inc(P, StrLen(P) + 1);
      end;
    finally
      FreeEnvironmentStrings(Inicio);
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
  AOnLinha: TLinhaEvento; ATimeoutMs: Cardinal; AConverterOem: Boolean): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  LeituraPipe, EscritaPipe: THandle;
  Linha: string;
  Ambiente: string;
  Buffer: array[0..4095] of AnsiChar;
  Lidos, Disponiveis: DWORD;
  Pendente, Trecho: AnsiString;
  Codigo: DWORD;
  InicioTick: UInt64;
  Encerrado, Estourou: Boolean;

  procedure EmitirLinha(const ABytes: AnsiString);
  var
    Convertida: AnsiString;
  begin
    if AConverterOem and (Length(ABytes) > 0) then
    begin
      SetLength(Convertida, Length(ABytes));
      OemToCharBuffA(PAnsiChar(ABytes), PAnsiChar(Convertida), Length(ABytes));
      Linha := string(Convertida);
    end
    else
      Linha := string(ABytes);
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

  // Lê tudo o que já está no pipe sem bloquear. False se o pipe fechou.
  function LerDisponivel: Boolean;
  begin
    Result := True;
    while PeekNamedPipe(LeituraPipe, nil, 0, nil, @Disponiveis, nil) do
    begin
      if Disponiveis = 0 then
        Exit;
      if not ReadFile(LeituraPipe, Buffer, SizeOf(Buffer), Lidos, nil) or (Lidos = 0) then
        Exit(False);
      SetString(Trecho, PAnsiChar(@Buffer[0]), Lidos);
      Pendente := Pendente + Trecho;
      ProcessarPendente(False);
    end;
    Result := False; // PeekNamedPipe falhou: pipe fechado
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
      InicioTick := GetTickCount64;
      Encerrado := False;
      Estourou := False;
      // Laço de polling: drena o pipe, confere se o processo acabou, confere o tempo limite.
      // Não usa ReadFile bloqueante para que um processo pendurado possa ser encerrado.
      repeat
        if not LerDisponivel then
          Break;
        if WaitForSingleObject(PI.hProcess, 100) = WAIT_OBJECT_0 then
        begin
          Encerrado := True;
          LerDisponivel;
          Break;
        end;
        if (ATimeoutMs > 0) and (GetTickCount64 - InicioTick > ATimeoutMs) then
        begin
          Estourou := True;
          TerminateProcess(PI.hProcess, DWORD(CodigoTimeout));
          WaitForSingleObject(PI.hProcess, 5000);
          LerDisponivel;
          Break;
        end;
      until False;
      if not Encerrado and not Estourou then
        // pipe fechou antes do fim do processo: espera o término (sem limite se ATimeoutMs = 0)
        if ATimeoutMs = 0 then
          WaitForSingleObject(PI.hProcess, INFINITE)
        else if WaitForSingleObject(PI.hProcess, ATimeoutMs) <> WAIT_OBJECT_0 then
        begin
          Estourou := True;
          TerminateProcess(PI.hProcess, DWORD(CodigoTimeout));
          WaitForSingleObject(PI.hProcess, 5000);
        end;
      ProcessarPendente(True);
      if Estourou then
      begin
        if Assigned(AOnLinha) then
          AOnLinha(Format('Processo encerrado por tempo limite (%d s)', [ATimeoutMs div 1000]));
        Result := CodigoTimeout;
      end
      else
      begin
        if not GetExitCodeProcess(PI.hProcess, Codigo) then
          Codigo := DWORD(-1);
        Result := Integer(Codigo);
      end;
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
