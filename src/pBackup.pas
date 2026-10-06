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

  // Progresso da cópia do .fdb: bytes copiados e tamanho total (chamado na thread do backup)
  TProgressoEvento = reference to procedure(ACopiados, ATotal: Int64);

  TBackup = class
  private
    FConfig: TConfig;
    FLog: TLog;
    FExecutor: TExecutor;
    FAgora: TDateTime;
    FEspacoLivreFixo: Int64;
    FTimeoutMs: Cardinal;
    FOnProgresso: TProgressoEvento;
    function Momento: TDateTime;
    function NomesBancos: TArray<string>;
    function Ambiente: TStrings;
    function Rodar(const AExe, AArgs: string; out AUltimaLinha: string): Integer;
    function MarcadorLock(const ANome: string): string;
    function CopiarArquivo(const AOrigem, ADestino: string; out AErro: string): Boolean;
  public
    constructor Create(AConfig: TConfig; ALog: TLog; AExecutor: TExecutor = nil);
    function Executar: Boolean;
    function ExecutarBanco(const ABanco: TBancoConfig): TResultadoBanco;
    function EspacoLivre(const APasta: string): Int64; virtual;
    procedure AplicarRetencao;
    // AInicio: hora de início da execução; é o que o timer compara com a data de hoje
    procedure GravarStatus(const AResultados: TArray<TResultadoBanco>; AInicio: TDateTime);
    class function NomeArquivoBackup(const ADestino, ANome: string; AQuando: TDateTime;
      const AExt: string): string;
    class function CasaPadraoRetencao(const ANomeArquivo: string;
      const ANomes: TArray<string>): Boolean;
    // Data embutida no nome (NOME_AAAA-MM-DD_HHNN.* ou backup_AAAA-MM-DD.log); False se não casa
    class function DataDoNome(const ANomeArquivo: string; out AData: TDateTime): Boolean;
    class function LerUltimaExecucao(const ADestino: string): TDateTime;
    // Mutex global que impede a tarefa agendada e a tela de rodarem ao mesmo tempo
    class function NomeMutexExecucao: string;
    class function OutroEmAndamento: Boolean;
    property Agora: TDateTime read FAgora write FAgora;
    property EspacoLivreFixo: Int64 read FEspacoLivreFixo write FEspacoLivreFixo;
    // Tempo máximo de cada gbak/nbackup; 0 = sem limite. Padrão 6 h.
    property TimeoutMs: Cardinal read FTimeoutMs write FTimeoutMs;
    property OnProgresso: TProgressoEvento read FOnProgresso write FOnProgresso;
  end;

implementation

uses
  Winapi.Windows, System.IOUtils, System.IniFiles, System.StrUtils, System.DateUtils,
  System.Character;

// TFile.GetSize nao existe no Delphi 10.3
function TamanhoArquivo(const AArquivo: string): Int64;
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst(AArquivo, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    System.SysUtils.FindClose(SR);
  end;
end;

constructor TBackup.Create(AConfig: TConfig; ALog: TLog; AExecutor: TExecutor);
begin
  inherited Create;
  FConfig := AConfig;
  FLog := ALog;
  FEspacoLivreFixo := -1;
  FTimeoutMs := 6 * 60 * 60 * 1000;
  if Assigned(AExecutor) then
    FExecutor := AExecutor
  else
    FExecutor := function(const AExe, AArgs: string; AAmbiente: TStrings; AOnLinha: TLinhaEvento;
      ATimeoutMs: Cardinal): Integer
      begin
        Result := ExecutarProcesso(AExe, AArgs, AAmbiente, AOnLinha, ATimeoutMs);
      end;
end;

class function TBackup.NomeMutexExecucao: string;
begin
  Result := 'Global\FirebirdBackup_Execucao';
end;

class function TBackup.OutroEmAndamento: Boolean;
var
  M: THandle;
begin
  M := CreateMutex(nil, True, PChar(NomeMutexExecucao));
  Result := (M <> 0) and (GetLastError = ERROR_ALREADY_EXISTS);
  if M <> 0 then
  begin
    if not Result then
      ReleaseMutex(M);
    CloseHandle(M);
  end;
end;

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
      end, FTimeoutMs);
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

// Callback do CopyFileEx: repassa o andamento ao OnProgresso do TBackup apontado por lpData.
function RotinaProgresso(TotalFileSize, TotalBytesTransferred, StreamSize,
  StreamBytesTransferred: LARGE_INTEGER; dwStreamNumber, dwCallbackReason: DWORD;
  hSourceFile, hDestinationFile: THandle; lpData: Pointer): DWORD; stdcall;
var
  Backup: TBackup;
begin
  Backup := TBackup(lpData);
  if Assigned(Backup.FOnProgresso) then
    Backup.FOnProgresso(TotalBytesTransferred.QuadPart, TotalFileSize.QuadPart);
  Result := PROGRESS_CONTINUE;
end;

function TBackup.CopiarArquivo(const AOrigem, ADestino: string; out AErro: string): Boolean;
begin
  AErro := '';
  // Sem COPY_FILE_FAIL_IF_EXISTS: mesmo comportamento do CopyFile(..., False) que havia antes
  Result := CopyFileEx(PChar(AOrigem), PChar(ADestino), @RotinaProgresso, Self, nil, 0);
  if not Result then
    AErro := SysErrorMessage(GetLastError);
end;

function TBackup.ExecutarBanco(const ABanco: TBancoConfig): TResultadoBanco;
var
  Quando: TDateTime;
  Fbk, Fdb, Ultima, Erro: string;
  Codigo, CodigoN: Integer;
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
  Erro := '';
  Erros := TStringList.Create;
  try
   try
    FLog.Escrever('=== Banco ' + ABanco.Nome + ' (' + ABanco.Arquivo + ')');
    // 1. Recuperação de lock pendente. O marcador só sai quando o -N dá certo:
    //    se falhou por motivo transitório, a próxima execução tenta de novo.
    if TFile.Exists(MarcadorLock(ABanco.Nome)) then
    begin
      FLog.Escrever('Marcador de lock pendente encontrado; destravando antes de continuar');
      Codigo := Rodar(FConfig.Nbackup, '-N ' + Aspas(ABanco.Arquivo), Ultima);
      if Codigo = 0 then
        TFile.Delete(MarcadorLock(ABanco.Nome))
      else
        FLog.Escrever('Aviso: nbackup -N retornou ' + IntToStr(Codigo) + ' (' + Ultima +
          '); marcador mantido para nova tentativa');
    end;
    // 2. Espaço livre
    Necessario := 0;
    if FConfig.CopiaFbk then
      Inc(Necessario, TamanhoArquivo(ABanco.Arquivo));
    if FConfig.CopiaFdb then
      Inc(Necessario, TamanhoArquivo(ABanco.Arquivo));
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
        Result.TamanhoFbk := TamanhoArquivo(Fbk);
    end;
    // 4. nbackup
    if FConfig.CopiaFdb then
    begin
      Fdb := NomeArquivoBackup(FConfig.Destino, ABanco.Nome, Quando, '.fdb');
      // Marcador ANTES do -L: se o processo cair logo depois do -L, a próxima execução destrava.
      TFile.WriteAllText(MarcadorLock(ABanco.Nome), FormatDateTime('yyyy-mm-dd hh:nn:ss', Quando));
      Codigo := Rodar(FConfig.Nbackup, '-L ' + Aspas(ABanco.Arquivo), Ultima);
      if Codigo <> 0 then
      begin
        TFile.Delete(MarcadorLock(ABanco.Nome));
        Falha('nbackup -L retornou ' + IntToStr(Codigo) + ': ' + Ultima);
      end
      else
      begin
        try
          FLog.Escrever('Copiando ' + ABanco.Arquivo + ' -> ' + Fdb);
          if not CopiarArquivo(ABanco.Arquivo, Fdb, Erro) then
            Falha('cópia do arquivo falhou: ' + Erro);
        finally
          CodigoN := Rodar(FConfig.Nbackup, '-N ' + Aspas(ABanco.Arquivo), Ultima);
          if CodigoN <> 0 then
            Falha('nbackup -N retornou ' + IntToStr(CodigoN) + ': ' + Ultima)
          else
            TFile.Delete(MarcadorLock(ABanco.Nome));
        end;
        if TFile.Exists(Fdb) and (Erro = '') and (CodigoN = 0) then
        begin
          Codigo := Rodar(FConfig.Nbackup, '-F ' + Aspas(Fdb), Ultima);
          if Codigo <> 0 then
            Falha('nbackup -F retornou ' + IntToStr(Codigo) + ': ' + Ultima)
          else
            Result.TamanhoFdb := TamanhoArquivo(Fdb);
        end;
      end;
    end;
   except
    // Exceção inesperada (CreateProcess, disco, marcador) vira falha deste banco,
    // nunca derruba o processo: no --run isso deixaria a tarefa agendada pendurada.
    on E: Exception do
      Falha(E.ClassName + ': ' + E.Message);
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
  Inicio: TDateTime;
  Mutex: THandle;
begin
  Mutex := CreateMutex(nil, True, PChar(NomeMutexExecucao));
  if (Mutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    CloseHandle(Mutex);
    FLog.Escrever('Backup já em andamento em outro processo; esta execução foi ignorada');
    Exit(False);
  end;
  try
    Result := True;
    Inicio := Momento;
    FLog.Escrever('Início do backup');
    SetLength(Resultados, FConfig.Bancos.Count);
    for I := 0 to FConfig.Bancos.Count - 1 do
    begin
      Resultados[I] := ExecutarBanco(FConfig.Bancos[I]);
      Result := Result and Resultados[I].OK;
    end;
    try
      AplicarRetencao;
    except
      on E: Exception do
      begin
        FLog.Escrever('ERRO na retenção: ' + E.ClassName + ': ' + E.Message);
        Result := False;
      end;
    end;
    try
      GravarStatus(Resultados, Inicio);
    except
      on E: Exception do
      begin
        FLog.Escrever('ERRO ao gravar ultimo-status.ini: ' + E.ClassName + ': ' + E.Message);
        Result := False;
      end;
    end;
    FLog.Escrever('Fim do backup: ' + IfThen(Result, 'OK', 'ERRO'));
  finally
    if Mutex <> 0 then
    begin
      ReleaseMutex(Mutex);
      CloseHandle(Mutex);
    end;
  end;
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

// Verifica "AAAA-MM-DD" em S a partir de APos (1-based)
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

class function TBackup.DataDoNome(const ANomeArquivo: string; out AData: TDateTime): Boolean;
var
  Base: string;
  P, A, M, D, H, N: Integer;
begin
  Result := False;
  AData := 0;
  Base := ChangeFileExt(ANomeArquivo, '');
  if SameText(ExtractFileExt(ANomeArquivo), '.log') then
    P := 7                        // backup_AAAA-MM-DD: data começa na posição 8
  else
    P := Length(Base) - 15;       // NOME_AAAA-MM-DD_HHNN: '_' antes da data
  if (P < 1) or (Length(Base) < P + 10) then
    Exit;
  A := StrToIntDef(Copy(Base, P + 1, 4), -1);
  M := StrToIntDef(Copy(Base, P + 6, 2), -1);
  D := StrToIntDef(Copy(Base, P + 9, 2), -1);
  H := 0;
  N := 0;
  if not SameText(ExtractFileExt(ANomeArquivo), '.log') then
  begin
    H := StrToIntDef(Copy(Base, P + 12, 2), -1);
    N := StrToIntDef(Copy(Base, P + 14, 2), -1);
  end;
  if (A < 0) or (M < 0) or (D < 0) or (H < 0) or (N < 0) then
    Exit;
  Result := TryEncodeDateTime(A, M, D, H, N, 0, 0, AData);
end;

// A data considerada é a do NOME, não a do arquivo: CopyFile preserva a data da origem
// e um nbackup -F que falhe deixaria a cópia recém-feita com data antiga.
procedure TBackup.AplicarRetencao;
var
  Limite, DataArq: TDateTime;
  Arq: string;
  Nomes: TArray<string>;
begin
  Limite := Momento - FConfig.RetencaoDias;
  Nomes := NomesBancos;
  if not TDirectory.Exists(FConfig.Destino) then
    Exit;
  for Arq in TDirectory.GetFiles(FConfig.Destino) do
    if CasaPadraoRetencao(ExtractFileName(Arq), Nomes)
      and DataDoNome(ExtractFileName(Arq), DataArq) and (DataArq < Limite) then
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

procedure TBackup.GravarStatus(const AResultados: TArray<TResultadoBanco>; AInicio: TDateTime);
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
    Ini.WriteString('Geral', 'UltimaExecucao', FormatDateTime('yyyy-mm-dd hh:nn:ss', AInicio));
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
