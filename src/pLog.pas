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
