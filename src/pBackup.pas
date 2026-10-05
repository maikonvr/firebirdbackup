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
