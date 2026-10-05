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
    // schtasks é app de console: escreve em OEM; 60 s de limite
    Result := ExecutarProcesso(Schtasks, ArgumentosSchtasks(AExe, AHorario), nil,
      procedure(const L: string) begin Linhas.Add(L); end, 60000, True) = 0;
    ASaida := Linhas.Text.Trim;
  finally
    Linhas.Free;
  end;
end;

end.
